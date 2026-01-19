# Kong LLM Gateway - C4 Architecture

This document describes the system architecture using the C4 model (Context, Containers, Components, Code).

## Level 1: System Context Diagram

Shows the LLM Gateway in the context of its users and external systems.

```mermaid
C4Context
    title System Context Diagram - Kong LLM Gateway

    Person(developer, "Developer", "AI/ML engineer using LLM APIs")
    Person(analyst, "Analyst", "Business analyst querying data")
    Person(ops, "Ecommerce Ops", "Operations team")
    Person(admin, "Platform Admin", "Gateway administrator")

    System(kong_gateway, "Kong LLM Gateway", "API Gateway that routes, meters, and secures LLM requests")

    System_Ext(bedrock, "AWS Bedrock", "Managed LLM service with Claude, Titan models")
    System_Ext(cloudwatch, "CloudWatch", "AWS monitoring and logging")
    System_Ext(prometheus, "Prometheus", "Metrics collection")
    System_Ext(datadog, "Datadog", "Production APM and monitoring")

    Rel(developer, kong_gateway, "Uses", "HTTPS/REST")
    Rel(analyst, kong_gateway, "Uses", "HTTPS/REST")
    Rel(ops, kong_gateway, "Uses", "HTTPS/REST")
    Rel(admin, kong_gateway, "Manages", "Admin API")

    Rel(kong_gateway, bedrock, "Proxies to", "HTTPS + SigV4")
    Rel(kong_gateway, cloudwatch, "Sends metrics", "AWS SDK")
    Rel(kong_gateway, prometheus, "Exposes metrics", "/metrics")
    Rel(kong_gateway, datadog, "Sends telemetry", "DogStatsD")
```

## Level 2: Container Diagram

Shows the containers that make up the LLM Gateway system.

```mermaid
C4Container
    title Container Diagram - Kong LLM Gateway

    Person(user, "API Consumer", "Application using LLM APIs")

    Container_Boundary(eks, "EKS Cluster") {
        Container(kong, "Kong Gateway", "Kong OSS 3.6", "API Gateway with custom plugins for Bedrock routing")
        Container(config, "ConfigMap", "Kubernetes", "Declarative Kong configuration")
        Container(plugins, "Custom Plugins", "Lua", "bedrock-proxy, token-meter, guardrails")
    }

    Container_Boundary(aws, "AWS Services") {
        ContainerDb(bedrock_claude, "Claude Models", "Bedrock", "Opus, Sonnet, Haiku")
        ContainerDb(bedrock_titan, "Titan Models", "Bedrock", "Text generation")
        Container(iam, "IAM/IRSA", "AWS IAM", "Service account credentials")
        ContainerDb(cloudwatch, "CloudWatch", "AWS", "Logs and metrics")
    }

    Container_Boundary(observability, "Observability Stack") {
        Container(prometheus, "Prometheus", "TSDB", "Metrics collection")
        Container(grafana, "Grafana", "Dashboards", "Visualization (local)")
        Container(datadog, "Datadog", "SaaS", "Monitoring & Alerting (prod)")
    }

    Rel(user, kong, "Sends requests", "HTTPS")
    Rel(kong, config, "Reads", "Volume mount")
    Rel(kong, plugins, "Executes", "Lua PDK")
    Rel(kong, bedrock_claude, "InvokeModel", "HTTPS/SigV4")
    Rel(kong, bedrock_titan, "InvokeModel", "HTTPS/SigV4")
    Rel(kong, iam, "AssumeRole", "IRSA")
    Rel(kong, cloudwatch, "PutMetricData", "AWS SDK")
    Rel(kong, prometheus, "Scrapes", "/metrics")
    Rel(prometheus, datadog, "Remote write", "HTTPS")
    Rel(grafana, prometheus, "Queries", "PromQL")
```

## Level 3: Component Diagram

Shows the components within Kong Gateway.

```mermaid
C4Component
    title Component Diagram - Kong Gateway Plugins

    Container_Boundary(kong, "Kong Gateway") {
        Component(proxy, "Proxy", "nginx", "Core request routing")
        Component(auth, "Key Auth", "Plugin", "API key validation")
        Component(ratelimit, "Rate Limiting", "Plugin", "Request/token limits")
        Component(transform, "Request Transformer", "Plugin", "Header manipulation")
        Component(prometheus_plugin, "Prometheus", "Plugin", "Metrics export")

        Container_Boundary(custom, "Custom Plugins") {
            Component(bedrock_proxy, "Bedrock Proxy", "Lua", "Routes requests to Bedrock, SigV4 signing")
            Component(token_meter, "Token Meter", "Lua", "Counts tokens, tracks costs")
            Component(guardrails, "Guardrails", "Lua", "PCI/GDPR compliance, content filtering")
        }
    }

    System_Ext(bedrock, "AWS Bedrock", "LLM APIs")
    System_Ext(consumer, "API Consumer", "Client application")

    Rel(consumer, auth, "API Key", "Header")
    Rel(auth, ratelimit, "Validated", "Internal")
    Rel(ratelimit, guardrails, "Rate OK", "Internal")
    Rel(guardrails, transform, "Content OK", "Internal")
    Rel(transform, bedrock_proxy, "Transformed", "Internal")
    Rel(bedrock_proxy, bedrock, "InvokeModel", "HTTPS")
    Rel(bedrock, bedrock_proxy, "Response", "JSON")
    Rel(bedrock_proxy, token_meter, "Response", "Internal")
    Rel(token_meter, prometheus_plugin, "Metrics", "Internal")
    Rel(token_meter, consumer, "Response", "HTTPS")
```

## Level 4: Code Diagram (Sequence)

Shows the request flow through the system.

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Kong
    participant KeyAuth
    participant RateLimit
    participant Guardrails
    participant BedrockProxy
    participant TokenMeter
    participant Bedrock
    participant CloudWatch

    Client->>Kong: POST /v1/chat/developer
    Kong->>KeyAuth: Validate API Key
    KeyAuth-->>Kong: Consumer: developer-team

    Kong->>RateLimit: Check rate limits
    RateLimit-->>Kong: Within limits

    Kong->>Guardrails: Scan request content
    Note over Guardrails: Check for PII, SQL injection,<br/>credit card numbers

    alt Content blocked
        Guardrails-->>Client: 403 Forbidden
    else Content OK
        Guardrails-->>Kong: Content validated
    end

    Kong->>BedrockProxy: Route to Bedrock
    Note over BedrockProxy: Transform OpenAI format<br/>to Bedrock format

    BedrockProxy->>BedrockProxy: Select model (Claude Sonnet)
    BedrockProxy->>BedrockProxy: Sign request (SigV4)

    BedrockProxy->>Bedrock: InvokeModel
    Bedrock-->>BedrockProxy: Response + token usage

    BedrockProxy->>TokenMeter: Process response
    Note over TokenMeter: Extract token counts<br/>Calculate costs

    TokenMeter->>CloudWatch: PutMetricData (async)

    TokenMeter-->>Kong: Add usage headers
    Kong-->>Client: 200 OK + X-Token-Usage headers
```

## Deployment Diagram

Shows how components are deployed in AWS.

```mermaid
flowchart TB
    subgraph Internet
        client[API Clients]
    end

    subgraph AWS["AWS Region (us-east-1)"]
        subgraph VPC["VPC 10.0.0.0/16"]
            subgraph public["Public Subnets"]
                nlb[Network Load Balancer]
            end

            subgraph private["Private Subnets"]
                subgraph EKS["EKS Cluster"]
                    subgraph kong_ns["Namespace: kong"]
                        kong1[Kong Pod 1]
                        kong2[Kong Pod 2]
                        kong3[Kong Pod 3]
                    end

                    subgraph monitoring["Namespace: monitoring"]
                        prometheus[Prometheus]
                        grafana[Grafana]
                    end
                end
            end
        end

        subgraph bedrock["Bedrock Service"]
            claude[Claude Models]
            titan[Titan Models]
        end

        subgraph iam["IAM"]
            role[Kong Bedrock Role]
            oidc[OIDC Provider]
        end

        cloudwatch[CloudWatch]
    end

    client --> nlb
    nlb --> kong1 & kong2 & kong3
    kong1 & kong2 & kong3 --> bedrock
    kong1 & kong2 & kong3 --> cloudwatch
    kong1 & kong2 & kong3 -.-> oidc
    oidc -.-> role
    role -.-> bedrock
    prometheus --> kong1 & kong2 & kong3
    grafana --> prometheus
```

## Data Flow Diagram

Shows how data flows through the system with security boundaries.

```mermaid
flowchart LR
    subgraph External["External (Untrusted)"]
        client[API Client]
    end

    subgraph DMZ["DMZ"]
        nlb[NLB]
    end

    subgraph Internal["Internal (Trusted)"]
        subgraph kong["Kong Gateway"]
            auth[Authentication]
            guard[Guardrails]
            proxy[Bedrock Proxy]
            meter[Token Meter]
        end
    end

    subgraph AWS["AWS Services"]
        bedrock[Bedrock API]
        cw[CloudWatch]
    end

    client -->|1. HTTPS Request| nlb
    nlb -->|2. Forward| auth
    auth -->|3. Validate Key| guard
    guard -->|4. Scan Content| proxy
    proxy -->|5. SigV4 Request| bedrock
    bedrock -->|6. LLM Response| proxy
    proxy -->|7. Process| meter
    meter -->|8. Log Metrics| cw
    meter -->|9. Response| client

    style External fill:#ffcccc
    style DMZ fill:#ffffcc
    style Internal fill:#ccffcc
    style AWS fill:#ccccff
```

## RBAC Model

Shows the role-based access control structure.

```mermaid
flowchart TB
    subgraph Consumers["API Consumers"]
        admin[Admin]
        developer[Developer]
        analyst[Analyst]
        ops[Ecommerce Ops]
        guest[Guest]
    end

    subgraph Models["Available Models"]
        opus[Claude Opus 4]
        sonnet[Claude Sonnet 4]
        haiku[Claude Haiku]
        titan[Titan Text]
    end

    subgraph Limits["Rate Limits"]
        admin_limit[Unlimited]
        dev_limit[10 req/s<br/>100K tokens/day]
        analyst_limit[5 req/s<br/>50K tokens/day]
        ops_limit[3 req/s<br/>20K tokens/day]
        guest_limit[1 req/s<br/>1K tokens/day]
    end

    admin --> opus & sonnet & haiku & titan
    admin --> admin_limit

    developer --> sonnet & haiku
    developer --> dev_limit

    analyst --> haiku & titan
    analyst --> analyst_limit

    ops --> haiku
    ops --> ops_limit

    guest --> haiku
    guest --> guest_limit

    style admin fill:#ff9999
    style developer fill:#99ff99
    style analyst fill:#9999ff
    style ops fill:#ffff99
    style guest fill:#cccccc
```

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| API Gateway | Kong OSS 3.6 | Request routing, authentication, rate limiting |
| Plugins | Lua (Kong PDK) | Custom logic for Bedrock integration |
| Container | Docker / EKS | Containerized deployment |
| Infrastructure | Terraform | Infrastructure as Code |
| GitOps | ArgoCD | Kubernetes deployment automation |
| Monitoring | Prometheus + Grafana | Metrics and dashboards |
| APM | Datadog | Production monitoring |
| Cloud | AWS (EKS, Bedrock, IAM) | Managed services |
