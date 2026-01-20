# LiteLLM Gateway - Proxy & Token Metering

Questo documento spiega come funziona il gateway LiteLLM e come vengono misurati i token per utente.

## Indice

- [Architettura Overview](#architettura-overview)
- [Flusso di una Richiesta](#flusso-di-una-richiesta)
- [Autenticazione e Utenti](#autenticazione-e-utenti)
- [Token Metering](#token-metering)
- [Budget Management](#budget-management)
- [Metriche Prometheus](#metriche-prometheus)

---

## Architettura Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              LiteLLM Gateway                                     │
│                                                                                  │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐             │
│  │   Client   │──▶│  API Key   │──▶│   Budget   │──▶│   Model    │             │
│  │  Request   │   │   Auth     │   │   Check    │   │   Router   │             │
│  └────────────┘   └────────────┘   └────────────┘   └────────────┘             │
│                                                            │                    │
│                                                            ▼                    │
│                                                     ┌────────────┐             │
│                                                     │  Bedrock   │             │
│                                                     │   Proxy    │             │
│                                                     └────────────┘             │
│                                                            │                    │
│                                                            ▼                    │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐             │
│  │  Response  │◀──│  Metrics   │◀──│   Token    │◀──│  Bedrock   │             │
│  │  to Client │   │   Export   │   │   Counter  │   │  Response  │             │
│  └────────────┘   └────────────┘   └────────────┘   └────────────┘             │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Flusso di una Richiesta

### Sequence Diagram Completo

```mermaid
sequenceDiagram
    autonumber
    participant Client as Claude Code
    participant CF as CloudFront
    participant ALB as ALB
    participant LiteLLM as LiteLLM Proxy
    participant DB as Internal State
    participant Bedrock as AWS Bedrock
    participant VM as Victoria Metrics

    %% Request Phase
    Client->>CF: POST /v1/chat/completions<br/>Authorization: Bearer sk-xxx
    CF->>ALB: Forward (TLS terminated)
    ALB->>LiteLLM: Route to LiteLLM service

    %% Authentication Phase
    rect rgb(255, 240, 240)
        Note over LiteLLM,DB: Authentication Phase
        LiteLLM->>DB: Lookup API Key (sk-xxx)
        DB-->>LiteLLM: User: user_123<br/>Budget: $10/month<br/>Spend: $3.50
    end

    %% Budget Check Phase
    rect rgb(255, 255, 240)
        Note over LiteLLM: Budget Check Phase
        LiteLLM->>LiteLLM: Check: $3.50 < $10?
        alt Budget Exceeded
            LiteLLM-->>Client: 429 Budget Exceeded
        end
    end

    %% Model Routing Phase
    rect rgb(240, 255, 240)
        Note over LiteLLM,Bedrock: Model Routing Phase
        LiteLLM->>LiteLLM: Map model name<br/>claude-haiku-4-5 → bedrock/anthropic.claude-3-5-haiku
        LiteLLM->>LiteLLM: Transform request<br/>OpenAI format → Bedrock format
        LiteLLM->>LiteLLM: Sign request (AWS SigV4)
        LiteLLM->>Bedrock: InvokeModel
    end

    %% Response Phase
    rect rgb(240, 240, 255)
        Note over Bedrock,LiteLLM: Response Phase
        Bedrock-->>LiteLLM: Response + Usage<br/>input_tokens: 150<br/>output_tokens: 500
    end

    %% Token Counting Phase
    rect rgb(255, 240, 255)
        Note over LiteLLM,DB: Token Metering Phase
        LiteLLM->>LiteLLM: Calculate cost<br/>150 × $0.25/1M + 500 × $1.25/1M<br/>= $0.000663
        LiteLLM->>DB: Update user spend<br/>$3.50 + $0.000663 = $3.500663
        LiteLLM->>LiteLLM: Record Prometheus metrics
    end

    %% Return Response
    LiteLLM-->>Client: 200 OK + Response

    %% Async Metrics Scrape
    Note over VM,LiteLLM: Async (every 15s)
    VM->>LiteLLM: GET /metrics/
    LiteLLM-->>VM: Prometheus metrics
```

---

## Autenticazione e Utenti

### Struttura Utente

```mermaid
erDiagram
    USER {
        string user_id PK
        string user_email
        float max_budget
        string budget_duration
        float spend
        datetime budget_reset_at
    }

    API_KEY {
        string key_id PK
        string key_hash
        string key_alias
        string user_id FK
        datetime created_at
        datetime expires_at
    }

    USAGE {
        string usage_id PK
        string user_id FK
        string model
        int input_tokens
        int output_tokens
        float cost
        datetime timestamp
    }

    USER ||--o{ API_KEY : has
    USER ||--o{ USAGE : generates
```

### Flusso Autenticazione

```mermaid
flowchart TD
    A[Request with API Key] --> B{Key exists?}
    B -->|No| C[401 Unauthorized]
    B -->|Yes| D{Key expired?}
    D -->|Yes| E[401 Key Expired]
    D -->|No| F{Key revoked?}
    F -->|Yes| G[401 Key Revoked]
    F -->|No| H[Load User Context]
    H --> I{User blocked?}
    I -->|Yes| J[403 User Blocked]
    I -->|No| K[Continue to Budget Check]

    style C fill:#ffcccc
    style E fill:#ffcccc
    style G fill:#ffcccc
    style J fill:#ffcccc
    style K fill:#ccffcc
```

---

## Token Metering

### Come Vengono Contati i Token

```mermaid
flowchart LR
    subgraph Request["Request Processing"]
        A[User Prompt] --> B[Tokenizer]
        B --> C[Input Tokens]
    end

    subgraph Bedrock["AWS Bedrock"]
        D[Model Processing]
    end

    subgraph Response["Response Processing"]
        E[Model Output] --> F[Output Tokens]
    end

    subgraph Metering["Token Metering"]
        G[Input Tokens<br/>from Bedrock response]
        H[Output Tokens<br/>from Bedrock response]
        I[Calculate Cost]
        J[Update User Spend]
        K[Export Metrics]
    end

    C --> D
    D --> E
    F --> G
    G --> I
    H --> I
    I --> J
    I --> K
```

### Calcolo Costo

```mermaid
flowchart TD
    subgraph Input["Input Cost"]
        A[Input Tokens: 150]
        B[Haiku Price: $0.25/1M]
        C["Cost: 150 × 0.25 / 1,000,000<br/>= $0.0000375"]
    end

    subgraph Output["Output Cost"]
        D[Output Tokens: 500]
        E[Haiku Price: $1.25/1M]
        F["Cost: 500 × 1.25 / 1,000,000<br/>= $0.000625"]
    end

    subgraph Total["Total Cost"]
        G["Total: $0.0000375 + $0.000625<br/>= $0.0006625"]
    end

    A --> C
    B --> C
    D --> F
    E --> F
    C --> G
    F --> G
```

### Prezzi per Modello

| Modello | Input ($/1M tokens) | Output ($/1M tokens) | Esempio 1K tokens |
|---------|---------------------|----------------------|-------------------|
| Claude Haiku 4.5 | $0.25 | $1.25 | $0.0015 |
| Claude Sonnet 4.5 | $3.00 | $15.00 | $0.018 |
| Claude Opus 4.5 | $15.00 | $75.00 | $0.09 |

---

## Budget Management

### Ciclo di Vita del Budget

```mermaid
stateDiagram-v2
    [*] --> Active: User Created
    Active --> Warning: Spend > 80%
    Warning --> Exceeded: Spend >= 100%
    Exceeded --> Active: Budget Reset
    Warning --> Active: Budget Reset
    Active --> Active: Budget Reset

    note right of Active
        User can make requests
        Spend tracked per request
    end note

    note right of Warning
        User notified
        Requests still allowed
    end note

    note right of Exceeded
        Requests blocked (429)
        Until budget reset
    end note
```

### Budget Check Flow

```mermaid
flowchart TD
    A[Incoming Request] --> B[Get User Budget Info]
    B --> C{Budget Duration?}

    C -->|daily| D[Check daily spend]
    C -->|weekly| E[Check weekly spend]
    C -->|monthly| F[Check monthly spend]

    D --> G{Spend < Max Budget?}
    E --> G
    F --> G

    G -->|Yes| H[Allow Request]
    G -->|No| I[429 Budget Exceeded]

    H --> J[Process Request]
    J --> K[Get Token Usage from Response]
    K --> L[Calculate Cost]
    L --> M[Update User Spend]
    M --> N[Return Response]

    style H fill:#ccffcc
    style I fill:#ffcccc
```

### Reset del Budget

```mermaid
sequenceDiagram
    participant User
    participant LiteLLM
    participant DB

    Note over User,DB: Daily Budget Reset (midnight UTC)

    User->>LiteLLM: Request at 23:59 UTC
    LiteLLM->>DB: Check budget<br/>Spend: $9.50 / $10
    DB-->>LiteLLM: OK (under budget)
    LiteLLM-->>User: 200 OK

    Note over DB: Clock strikes 00:00 UTC

    DB->>DB: Reset daily budgets<br/>Spend: $0 / $10

    User->>LiteLLM: Request at 00:01 UTC
    LiteLLM->>DB: Check budget<br/>Spend: $0 / $10
    DB-->>LiteLLM: OK (budget reset)
    LiteLLM-->>User: 200 OK
```

---

## Metriche Prometheus

### Metriche Esportate

```mermaid
flowchart TB
    subgraph LiteLLM["LiteLLM Proxy"]
        A[Request Handler]
        B[Prometheus Callback]
    end

    subgraph Metrics["Prometheus Metrics"]
        C[litellm_proxy_total_requests_metric_total]
        D[litellm_total_tokens_metric_total]
        E[litellm_spend_metric_total]
        F[litellm_llm_api_latency_metric_bucket]
    end

    subgraph Labels["Labels per Metric"]
        G["user, model, status_code"]
    end

    A --> B
    B --> C
    B --> D
    B --> E
    B --> F

    C --- G
    D --- G
    E --- G
```

### Struttura Metriche

| Metrica | Tipo | Labels | Descrizione |
|---------|------|--------|-------------|
| `litellm_proxy_total_requests_metric_total` | Counter | user, model, status_code | Totale richieste |
| `litellm_total_tokens_metric_total` | Counter | user, model, type (input/output) | Totale token |
| `litellm_spend_metric_total` | Counter | user, model | Spesa in USD |
| `litellm_llm_api_latency_metric_bucket` | Histogram | model | Latenza API |

### Query PromQL Utili

```promql
# Token totali per utente (ultime 24h)
sum(increase(litellm_total_tokens_metric_total[24h])) by (user)

# Spesa per utente (ultime 24h)
sum(increase(litellm_spend_metric_total[24h])) by (user)

# Richieste per modello
sum(rate(litellm_proxy_total_requests_metric_total[5m])) by (model)

# Latenza P95 per modello
histogram_quantile(0.95,
  sum(rate(litellm_llm_api_latency_metric_bucket[5m])) by (le, model)
)

# Top 5 utenti per spesa
topk(5, sum(litellm_spend_metric_total) by (user))
```

---

## Flusso Completo: Da Request a Dashboard

```mermaid
flowchart TB
    subgraph Client["Client Layer"]
        A[Claude Code]
    end

    subgraph Edge["Edge Layer"]
        B[CloudFront]
    end

    subgraph Gateway["Gateway Layer"]
        C[ALB]
        D[LiteLLM Proxy]
    end

    subgraph Backend["Backend Layer"]
        E[AWS Bedrock]
    end

    subgraph Observability["Observability Layer"]
        F[Victoria Metrics]
        G[Grafana]
    end

    A -->|1. HTTPS Request| B
    B -->|2. Forward| C
    C -->|3. Route| D
    D -->|4. InvokeModel| E
    E -->|5. Response + Tokens| D
    D -->|6. Response| A

    D -.->|7. Expose /metrics/| F
    F -.->|8. Query| G

    style A fill:#e1f5fe
    style D fill:#fff3e0
    style E fill:#f3e5f5
    style G fill:#e8f5e9
```

### Dashboard Grafana

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        LLM Usage Overview                                    │
├─────────────────┬─────────────────┬─────────────────┬───────────────────────┤
│  Total Requests │  Total Tokens   │  Total Spend    │  Active Users         │
│     12,456      │     2.3M        │    $45.67       │       8               │
├─────────────────┴─────────────────┴─────────────────┴───────────────────────┤
│                                                                              │
│  Token Usage by User (24h)                                                   │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ user_123  ████████████████████████████████████  850K                  │ │
│  │ user_456  ████████████████████████  620K                              │ │
│  │ user_789  ████████████████  480K                                      │ │
│  │ user_abc  ████████  350K                                              │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  Spend by Model                      │  Requests Over Time                   │
│  ┌─────────────────────────────────┐ │  ┌─────────────────────────────────┐ │
│  │         ╭───╮                   │ │  │    ╱╲    ╱╲                     │ │
│  │        ╱     ╲   Haiku: 65%     │ │  │   ╱  ╲  ╱  ╲    ╱╲             │ │
│  │       ╱       ╲                 │ │  │  ╱    ╲╱    ╲  ╱  ╲            │ │
│  │      ╱ Sonnet: ╲ 30%            │ │  │ ╱            ╲╱    ╲           │ │
│  │     ╱   Opus:   ╲ 5%            │ │  │╱                    ╲          │ │
│  └─────────────────────────────────┘ │  └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Riepilogo

1. **Autenticazione**: API key → User lookup → Budget check
2. **Routing**: Model name mapping → Request transformation → SigV4 signing
3. **Metering**: Token count from Bedrock response → Cost calculation → Spend update
4. **Observability**: Prometheus metrics → Victoria Metrics → Grafana dashboards
