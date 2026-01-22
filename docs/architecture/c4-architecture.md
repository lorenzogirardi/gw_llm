# LiteLLM Gateway - C4 Architecture

This document describes the system architecture using the C4 model (Context, Containers, Components, Code).

## Level 1: System Context Diagram

Shows the LLM Gateway in the context of its users and external systems.

```mermaid
C4Context
    title System Context Diagram - LiteLLM Gateway

    Person(developer, "Developer", "Uses Claude Code or direct API")
    Person(admin, "Platform Admin", "Manages gateway and users")

    System(litellm_gateway, "LiteLLM Gateway", "OpenAI-compatible API proxy with usage tracking")

    System_Ext(bedrock, "AWS Bedrock", "Managed LLM service with Claude models")
    System_Ext(cloudwatch, "CloudWatch", "AWS monitoring and logging")

    Rel(developer, litellm_gateway, "API requests", "HTTPS")
    Rel(admin, litellm_gateway, "Manages users/keys", "Admin API")

    Rel(litellm_gateway, bedrock, "InvokeModel", "HTTPS + SigV4")
    Rel(litellm_gateway, cloudwatch, "Logs", "AWS SDK")
```

## Level 2: Container Diagram

Shows the containers that make up the LLM Gateway system.

```mermaid
C4Container
    title Container Diagram - LiteLLM Gateway

    Person(user, "API Consumer", "Application using LLM APIs")
    Person(admin, "Admin", "VPC/VPN access only")

    Container_Boundary(aws, "AWS Cloud") {
        Container_Boundary(vpc, "VPC") {
            Container(cloudfront, "CloudFront", "CDN", "TLS termination, admin endpoints blocked")
            Container(alb, "Application LB", "AWS ALB", "Load balancing, routing")

            Container_Boundary(ecs, "ECS Cluster") {
                Container(litellm, "LiteLLM Proxy", "Python/FastAPI", "OpenAI-compatible API, model routing")
                Container(langfuse, "Langfuse", "Next.js", "LLM observability and tracing")
                Container(grafana, "Grafana", "Grafana 11", "Dashboards and visualization")
                Container(victoria, "Victoria Metrics", "VictoriaMetrics", "Metrics storage (Prometheus-compatible)")
            }

            ContainerDb(postgres, "PostgreSQL", "RDS db.t4g.micro", "Users, API keys, spend tracking, Langfuse data")
        }

        ContainerDb(bedrock_claude, "Claude Models", "Bedrock", "Haiku, Sonnet, Opus")
        Container(secrets, "Secrets Manager", "AWS", "API keys, master key, DB URL, Langfuse keys")
    }

    Rel(user, cloudfront, "HTTPS /v1/*", "443")
    Rel(admin, alb, "HTTP /user/*", "VPC only")
    Rel(cloudfront, alb, "HTTP", "80")
    Rel(alb, litellm, "HTTP", "/v1/*")
    Rel(alb, langfuse, "HTTP", "/langfuse/*")
    Rel(alb, grafana, "HTTP", "/grafana/*")
    Rel(litellm, bedrock_claude, "InvokeModel", "HTTPS/SigV4")
    Rel(litellm, postgres, "Prisma ORM", "5432")
    Rel(litellm, langfuse, "Traces", "Langfuse callback")
    Rel(langfuse, postgres, "Store traces", "5432")
    Rel(litellm, secrets, "GetSecret", "AWS SDK")
    Rel(victoria, litellm, "Scrapes", "/metrics/")
    Rel(grafana, victoria, "Queries", "PromQL")
```

## Level 3: Component Diagram

Shows the components within LiteLLM Gateway.

```mermaid
C4Component
    title Component Diagram - LiteLLM Proxy

    Container_Boundary(litellm, "LiteLLM Proxy") {
        Component(api, "OpenAI API", "FastAPI", "OpenAI-compatible endpoints")
        Component(router, "Model Router", "Python", "Routes to configured models")
        Component(auth, "Authentication", "Python", "API key validation")
        Component(budget, "Budget Manager", "Python", "User budgets and limits")
        Component(prometheus, "Prometheus Callback", "Python", "Metrics export")
        Component(langfuse_cb, "Langfuse Callback", "Python", "LLM trace logging")
        Component(prisma, "Prisma ORM", "Python", "Database operations")
    }

    System_Ext(bedrock, "AWS Bedrock", "LLM APIs")
    System_Ext(consumer, "API Consumer", "Client application")
    System_Ext(langfuse, "Langfuse", "LLM observability")
    ContainerDb(postgres, "PostgreSQL", "User/Key/Spend data")

    Rel(consumer, api, "POST /v1/chat/completions", "HTTPS")
    Rel(api, auth, "Validate key", "Internal")
    Rel(auth, prisma, "Lookup key", "SQL")
    Rel(prisma, postgres, "Query", "5432")
    Rel(auth, budget, "Check budget", "Internal")
    Rel(budget, router, "Route request", "Internal")
    Rel(router, bedrock, "InvokeModel", "HTTPS")
    Rel(bedrock, router, "Response", "JSON")
    Rel(router, prisma, "Update spend", "SQL")
    Rel(router, prometheus, "Record metrics", "Internal")
    Rel(router, langfuse_cb, "Log trace", "Internal")
    Rel(langfuse_cb, langfuse, "Send trace", "HTTPS")
    Rel(prometheus, consumer, "Response", "HTTPS")
```

## Level 4: Sequence Diagram

Shows the request flow through the system.

```mermaid
sequenceDiagram
    autonumber
    participant Client as Claude Code
    participant CF as CloudFront
    participant ALB as ALB
    participant LiteLLM as LiteLLM Proxy
    participant PG as PostgreSQL
    participant Bedrock as AWS Bedrock
    participant LF as Langfuse
    participant VM as Victoria Metrics

    Client->>CF: POST /v1/chat/completions
    CF->>ALB: Forward request
    ALB->>LiteLLM: Route to LiteLLM

    LiteLLM->>PG: Lookup API Key
    PG-->>LiteLLM: Key + User info

    alt Invalid Key
        LiteLLM-->>Client: 401 Unauthorized
    else Valid Key
        LiteLLM->>PG: Check user budget
        PG-->>LiteLLM: Current spend
    end

    alt Budget exceeded
        LiteLLM-->>Client: 429 Budget Exceeded
    else Budget OK
        LiteLLM->>LiteLLM: Select model (claude-haiku-4-5)
    end

    LiteLLM->>Bedrock: InvokeModel (SigV4 signed)
    Bedrock-->>LiteLLM: Response + token usage

    LiteLLM->>PG: Update spend
    LiteLLM->>LiteLLM: Record metrics
    LiteLLM->>LF: Send trace (async)
    Note over LiteLLM,LF: tokens, latency, cost, input/output

    LiteLLM-->>Client: 200 OK + response

    VM->>LiteLLM: Scrape /metrics/
    LiteLLM-->>VM: Prometheus metrics
```

## Deployment Diagram

Shows how components are deployed in AWS.

```mermaid
flowchart TB
    subgraph Internet
        client[API Clients<br/>Claude Code]
    end

    subgraph AWS["AWS Region (us-west-1)"]
        cf[CloudFront Distribution<br/>Admin endpoints blocked]

        subgraph VPC["VPC 10.10.0.0/16"]
            subgraph public["Public Subnets"]
                alb[Application Load Balancer]
                nat[NAT Instance]
            end

            subgraph private["Private Subnets"]
                subgraph ECS["ECS Cluster (Fargate)"]
                    litellm[LiteLLM Service<br/>1 vCPU, 2GB]
                    langfuse[Langfuse Service<br/>0.5 vCPU, 1GB]
                    grafana[Grafana Service<br/>0.25 vCPU, 0.5GB]
                    victoria[Victoria Metrics<br/>0.25 vCPU, 0.5GB]
                end

                rds[(RDS PostgreSQL<br/>db.t4g.micro)]
            end
        end

        subgraph bedrock["Bedrock Service"]
            haiku[Claude Haiku 4.5]
            sonnet[Claude Sonnet 4.5]
            opus[Claude Opus 4.5]
        end

        secrets[Secrets Manager]
        ecr[ECR Repositories]
    end

    client --> cf
    cf --> alb
    alb --> litellm
    alb --> langfuse
    alb --> grafana
    litellm --> nat
    nat --> bedrock
    litellm <--> rds
    litellm --> langfuse
    langfuse <--> rds
    litellm -.-> secrets
    victoria --> litellm
    grafana --> victoria

    style haiku fill:#90EE90
    style sonnet fill:#FFD700
    style opus fill:#FF6B6B
    style rds fill:#336791,color:#fff
    style cf fill:#ffcccc
    style langfuse fill:#e6f3ff
```

## Data Flow Diagram

Shows how data flows through the system with security boundaries.

```mermaid
flowchart LR
    subgraph External["External (Internet)"]
        client[API Client]
        admin[Admin VPN]
    end

    subgraph Edge["Edge (CloudFront)"]
        cf[CDN + TLS<br/>Blocks /user/*, /key/*]
    end

    subgraph DMZ["DMZ (Public Subnet)"]
        alb[ALB]
    end

    subgraph Internal["Internal (Private Subnet)"]
        subgraph litellm["LiteLLM"]
            auth[Auth]
            budget[Budget]
            proxy[Model Proxy]
        end
        langfuse[Langfuse]
        metrics[Victoria Metrics]
        pg[(PostgreSQL)]
    end

    subgraph AWS["AWS Services"]
        bedrock[Bedrock API]
        sm[Secrets Manager]
    end

    client -->|1. HTTPS /v1/*| cf
    admin -->|Admin /user/*| alb
    cf -->|2. HTTP| alb
    alb -->|3. Route| auth
    auth -->|4. Query key| pg
    auth -->|5. Validate| budget
    budget -->|6. Check spend| pg
    budget -->|7. Route| proxy
    proxy -->|8. SigV4| bedrock
    bedrock -->|9. Response| proxy
    proxy -->|10. Update spend| pg
    proxy -->|11. Metrics| metrics
    proxy -->|12. Trace| langfuse
    langfuse -->|13. Store| pg
    proxy -->|14. Response| client

    style External fill:#ffcccc
    style Edge fill:#ffffcc
    style DMZ fill:#ffe4b5
    style Internal fill:#ccffcc
    style AWS fill:#ccccff
    style pg fill:#336791,color:#fff
    style langfuse fill:#e6f3ff
```

## User Budget Model

Shows how user budgets and limits work.

```mermaid
flowchart TB
    subgraph Users["LiteLLM Users"]
        admin[Admin User<br/>Unlimited]
        dev[Developer User<br/>$10/month]
        test[Test User<br/>$1/month]
    end

    subgraph Models["Available Models"]
        haiku[Claude Haiku 4.5<br/>$0.25/$1.25 per 1M]
        sonnet[Claude Sonnet 4.5<br/>$3/$15 per 1M]
        opus[Claude Opus 4.5<br/>$15/$75 per 1M]
    end

    subgraph Tracking["Usage Tracking"]
        tokens[Token Counter]
        spend[Spend Calculator]
        budget[Budget Enforcer]
    end

    admin --> haiku & sonnet & opus
    dev --> haiku & sonnet
    test --> haiku

    haiku & sonnet & opus --> tokens
    tokens --> spend
    spend --> budget

    budget -->|Exceeded| block[429 Budget Exceeded]
    budget -->|OK| allow[Process Request]

    style admin fill:#ff9999
    style dev fill:#99ff99
    style test fill:#9999ff
    style block fill:#ffcccc
    style allow fill:#ccffcc
```

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| CDN | CloudFront | TLS termination, admin endpoint blocking |
| Load Balancer | ALB | Request routing, health checks |
| API Proxy | LiteLLM | OpenAI-compatible API, model routing |
| LLM Tracing | Langfuse | LLM observability, request/response logging |
| Compute | ECS Fargate | Serverless containers |
| Database | RDS PostgreSQL | Users, API keys, spend tracking, traces |
| Metrics | Victoria Metrics | Prometheus-compatible TSDB |
| Dashboards | Grafana | Visualization and alerting |
| LLM Backend | AWS Bedrock | Claude model hosting |
| Secrets | Secrets Manager | API keys, DB URL, master key, Langfuse keys |
| IaC | Terraform | Infrastructure as Code |

## Security Model

```mermaid
flowchart TB
    subgraph Public["Public Access (CloudFront)"]
        chat["/v1/chat/completions ✅"]
        models["/v1/models ✅"]
        health["/health/* ✅"]
        metrics["/metrics/ ✅"]
    end

    subgraph Blocked["Blocked from CloudFront (403)"]
        user["/user/* ❌"]
        key["/key/* ❌"]
        model["/model/* ❌"]
        spend["/spend/* ❌"]
    end

    subgraph Internal["Internal Access Only (ALB)"]
        user_alb["/user/* ✅"]
        key_alb["/key/* ✅"]
        model_alb["/model/* ✅"]
        spend_alb["/spend/* ✅"]
    end

    cf[CloudFront] --> Public
    cf -.->|403 Forbidden| Blocked
    alb[ALB Direct] --> Internal

    style Blocked fill:#ffcccc
    style Internal fill:#ccffcc
```
