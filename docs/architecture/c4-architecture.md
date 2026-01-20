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

    Container_Boundary(aws, "AWS Cloud") {
        Container_Boundary(vpc, "VPC") {
            Container(cloudfront, "CloudFront", "CDN", "TLS termination, caching")
            Container(alb, "Application LB", "AWS ALB", "Load balancing, routing")

            Container_Boundary(ecs, "ECS Cluster") {
                Container(litellm, "LiteLLM Proxy", "Python/FastAPI", "OpenAI-compatible API, model routing")
                Container(grafana, "Grafana", "Grafana 11", "Dashboards and visualization")
                Container(victoria, "Victoria Metrics", "VictoriaMetrics", "Metrics storage (Prometheus-compatible)")
            }
        }

        ContainerDb(bedrock_claude, "Claude Models", "Bedrock", "Haiku, Sonnet, Opus")
        Container(secrets, "Secrets Manager", "AWS", "API keys, master key")
    }

    Rel(user, cloudfront, "HTTPS", "443")
    Rel(cloudfront, alb, "HTTP", "80")
    Rel(alb, litellm, "HTTP", "/v1/*")
    Rel(alb, grafana, "HTTP", "/grafana/*")
    Rel(litellm, bedrock_claude, "InvokeModel", "HTTPS/SigV4")
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
    }

    System_Ext(bedrock, "AWS Bedrock", "LLM APIs")
    System_Ext(consumer, "API Consumer", "Client application")

    Rel(consumer, api, "POST /v1/chat/completions", "HTTPS")
    Rel(api, auth, "Validate key", "Internal")
    Rel(auth, budget, "Check budget", "Internal")
    Rel(budget, router, "Route request", "Internal")
    Rel(router, bedrock, "InvokeModel", "HTTPS")
    Rel(bedrock, router, "Response", "JSON")
    Rel(router, prometheus, "Record metrics", "Internal")
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
    participant Bedrock as AWS Bedrock
    participant VM as Victoria Metrics

    Client->>CF: POST /v1/chat/completions
    CF->>ALB: Forward request
    ALB->>LiteLLM: Route to LiteLLM

    LiteLLM->>LiteLLM: Validate API Key

    alt Invalid Key
        LiteLLM-->>Client: 401 Unauthorized
    else Valid Key
        LiteLLM->>LiteLLM: Check user budget
    end

    alt Budget exceeded
        LiteLLM-->>Client: 429 Budget Exceeded
    else Budget OK
        LiteLLM->>LiteLLM: Select model (claude-haiku-4-5)
    end

    LiteLLM->>Bedrock: InvokeModel (SigV4 signed)
    Bedrock-->>LiteLLM: Response + token usage

    LiteLLM->>LiteLLM: Record metrics
    Note over LiteLLM: tokens, latency, cost

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
        cf[CloudFront Distribution]

        subgraph VPC["VPC 10.10.0.0/16"]
            subgraph public["Public Subnets"]
                alb[Application Load Balancer]
                nat[NAT Instance]
            end

            subgraph private["Private Subnets"]
                subgraph ECS["ECS Cluster (Fargate)"]
                    litellm[LiteLLM Service<br/>0.5 vCPU, 1GB]
                    grafana[Grafana Service<br/>0.25 vCPU, 0.5GB]
                    victoria[Victoria Metrics<br/>0.25 vCPU, 0.5GB]
                end
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
    alb --> grafana
    litellm --> nat
    nat --> bedrock
    litellm -.-> secrets
    victoria --> litellm
    grafana --> victoria

    style haiku fill:#90EE90
    style sonnet fill:#FFD700
    style opus fill:#FF6B6B
```

## Data Flow Diagram

Shows how data flows through the system with security boundaries.

```mermaid
flowchart LR
    subgraph External["External (Internet)"]
        client[API Client]
    end

    subgraph Edge["Edge (CloudFront)"]
        cf[CDN + TLS]
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
        metrics[Victoria Metrics]
    end

    subgraph AWS["AWS Services"]
        bedrock[Bedrock API]
        sm[Secrets Manager]
    end

    client -->|1. HTTPS| cf
    cf -->|2. HTTP| alb
    alb -->|3. Route| auth
    auth -->|4. Validate| budget
    budget -->|5. Check| proxy
    proxy -->|6. SigV4| bedrock
    bedrock -->|7. Response| proxy
    proxy -->|8. Metrics| metrics
    proxy -->|9. Response| client

    style External fill:#ffcccc
    style Edge fill:#ffffcc
    style DMZ fill:#ffe4b5
    style Internal fill:#ccffcc
    style AWS fill:#ccccff
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
| CDN | CloudFront | TLS termination, edge caching |
| Load Balancer | ALB | Request routing, health checks |
| API Proxy | LiteLLM | OpenAI-compatible API, model routing |
| Compute | ECS Fargate | Serverless containers |
| Metrics | Victoria Metrics | Prometheus-compatible TSDB |
| Dashboards | Grafana | Visualization and alerting |
| LLM Backend | AWS Bedrock | Claude model hosting |
| Secrets | Secrets Manager | API keys, credentials |
| IaC | Terraform | Infrastructure as Code |
