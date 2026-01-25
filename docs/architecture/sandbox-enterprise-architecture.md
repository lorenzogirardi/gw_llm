# Stargate LLM Gateway - Sandbox Enterprise Architecture

**Version:** 1.0
**Environment:** Sandbox (Production-Ready)
**Region:** us-east-1
**Target Capacity:** 100 concurrent users

---

## Executive Summary

The Sandbox environment is a **production-ready** deployment of the Stargate LLM Gateway, designed to support 100 concurrent users with enterprise-grade reliability, security, and observability. This document outlines the architecture, scaling strategies, and high availability (HA) configurations.

---

## Architecture Overview

### High-Level Architecture Diagram

```
                                    ┌─────────────────────────────────────┐
                                    │           INTERNET                  │
                                    └──────────────┬──────────────────────┘
                                                   │
                                    ┌──────────────▼──────────────────────┐
                                    │         AWS CloudFront              │
                                    │    ┌─────────────────────────┐      │
                                    │    │   WAF (Advanced Rules)  │      │
                                    │    │  • Bot Control          │      │
                                    │    │  • IP Reputation        │      │
                                    │    │  • Rate Limiting        │      │
                                    │    │  • Common Rule Set      │      │
                                    │    └─────────────────────────┘      │
                                    │    Price Class: PriceClass_100      │
                                    │    SSL/TLS: AWS Certificate         │
                                    └──────────────┬──────────────────────┘
                                                   │ HTTPS (443)
                                                   │
                              ┌─────────────────────────────────────────────┐
                              │              AWS VPC (10.20.0.0/16)         │
                              │                  us-east-1                   │
                              │                                              │
                              │  ┌────────────────────────────────────────┐  │
                              │  │         PUBLIC SUBNETS (3 AZs)         │  │
                              │  │   us-east-1a    us-east-1b   us-east-1c│  │
                              │  │   10.20.101.0   10.20.102.0  10.20.103.0│ │
                              │  │                                        │  │
                              │  │  ┌──────────────────────────────────┐  │  │
                              │  │  │    Application Load Balancer     │  │  │
                              │  │  │         (Multi-AZ, HTTP:80)      │  │  │
                              │  │  └──────────────┬───────────────────┘  │  │
                              │  │                 │                      │  │
                              │  │  ┌──────────────┴───────────────┐      │  │
                              │  │  │       NAT Gateway (HA)       │      │  │
                              │  │  └──────────────────────────────┘      │  │
                              │  └────────────────────────────────────────┘  │
                              │                    │                         │
                              │  ┌─────────────────▼──────────────────────┐  │
                              │  │        PRIVATE SUBNETS (3 AZs)         │  │
                              │  │   us-east-1a    us-east-1b   us-east-1c│  │
                              │  │   10.20.1.0     10.20.2.0    10.20.3.0 │  │
                              │  │                                        │  │
                              │  │  ┌────────────────────────────────┐    │  │
                              │  │  │      ECS FARGATE CLUSTER       │    │  │
                              │  │  │                                │    │  │
                              │  │  │  ┌──────────┐  ┌──────────┐   │    │  │
                              │  │  │  │ LiteLLM  │  │ LiteLLM  │   │    │  │
                              │  │  │  │ Task 1   │  │ Task 2   │   │    │  │
                              │  │  │  │ (AZ-a)   │  │ (AZ-b)   │   │    │  │
                              │  │  │  └────┬─────┘  └────┬─────┘   │    │  │
                              │  │  │       │             │         │    │  │
                              │  │  │  ┌────┴─────┐  ┌────┴─────┐   │    │  │
                              │  │  │  │ Grafana  │  │ Grafana  │   │    │  │
                              │  │  │  │ Task 1   │  │ Task 2   │   │    │  │
                              │  │  │  └──────────┘  └──────────┘   │    │  │
                              │  │  │                                │    │  │
                              │  │  │  ┌──────────┐  ┌──────────┐   │    │  │
                              │  │  │  │ Langfuse │  │ Langfuse │   │    │  │
                              │  │  │  │ Task 1   │  │ Task 2   │   │    │  │
                              │  │  │  └────┬─────┘  └────┬─────┘   │    │  │
                              │  │  │       │             │         │    │  │
                              │  │  │  ┌────┴─────────────┴─────┐   │    │  │
                              │  │  │  │   Victoria Metrics     │   │    │  │
                              │  │  │  │   (Single + EFS)       │   │    │  │
                              │  │  │  └────────────┬───────────┘   │    │  │
                              │  │  │               │               │    │  │
                              │  │  └───────────────┼───────────────┘    │  │
                              │  │                  │                    │  │
                              │  │  ┌───────────────▼───────────────┐    │  │
                              │  │  │         Amazon EFS            │    │  │
                              │  │  │   (Multi-AZ, Encrypted)       │    │  │
                              │  │  │   /victoria-metrics-data      │    │  │
                              │  │  └───────────────────────────────┘    │  │
                              │  │                                        │  │
                              │  │  ┌───────────────────────────────┐    │  │
                              │  │  │     RDS PostgreSQL 16         │    │  │
                              │  │  │     db.r6g.large (Multi-AZ)   │    │  │
                              │  │  │     100GB GP3 Storage         │    │  │
                              │  │  └───────────────────────────────┘    │  │
                              │  └────────────────────────────────────────┘  │
                              └─────────────────────────────────────────────┘
                                                   │
                                    ┌──────────────▼──────────────────────┐
                                    │         AWS Bedrock                 │
                                    │    (Claude Models - us-east-1)      │
                                    │  • claude-haiku-4-5                 │
                                    │  • claude-sonnet-4-5                │
                                    │  • claude-opus-4-5                  │
                                    └─────────────────────────────────────┘
```

---

## Network Architecture

### VPC Design (3-AZ Deployment)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VPC: 10.20.0.0/16 (us-east-1)                        │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     AVAILABILITY ZONE: us-east-1a                    │   │
│  │  ┌─────────────────────┐    ┌─────────────────────┐                 │   │
│  │  │  Public Subnet      │    │  Private Subnet     │                 │   │
│  │  │  10.20.101.0/24     │    │  10.20.1.0/24       │                 │   │
│  │  │                     │    │                     │                 │   │
│  │  │  • NAT Gateway      │    │  • ECS Tasks        │                 │   │
│  │  │  • ALB Node         │    │  • RDS Primary      │                 │   │
│  │  │                     │    │  • EFS Mount Target │                 │   │
│  │  └─────────────────────┘    └─────────────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     AVAILABILITY ZONE: us-east-1b                    │   │
│  │  ┌─────────────────────┐    ┌─────────────────────┐                 │   │
│  │  │  Public Subnet      │    │  Private Subnet     │                 │   │
│  │  │  10.20.102.0/24     │    │  10.20.2.0/24       │                 │   │
│  │  │                     │    │                     │                 │   │
│  │  │  • ALB Node         │    │  • ECS Tasks        │                 │   │
│  │  │                     │    │  • RDS Standby      │                 │   │
│  │  │                     │    │  • EFS Mount Target │                 │   │
│  │  └─────────────────────┘    └─────────────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     AVAILABILITY ZONE: us-east-1c                    │   │
│  │  ┌─────────────────────┐    ┌─────────────────────┐                 │   │
│  │  │  Public Subnet      │    │  Private Subnet     │                 │   │
│  │  │  10.20.103.0/24     │    │  10.20.3.0/24       │                 │   │
│  │  │                     │    │                     │                 │   │
│  │  │  • ALB Node         │    │  • ECS Tasks        │                 │   │
│  │  │                     │    │  • EFS Mount Target │                 │   │
│  │  └─────────────────────┘    └─────────────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          Internet Gateway                            │   │
│  │                    (Attached to Public Subnets)                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

```
                    INBOUND REQUEST FLOW
                    ═══════════════════

    User Request (HTTPS)
           │
           ▼
    ┌──────────────┐
    │  CloudFront  │ ◄─── WAF Inspection
    │   (Edge)     │      • Bot Control
    └──────┬───────┘      • Rate Limiting
           │              • IP Reputation
           │ HTTP (80)
           ▼
    ┌──────────────┐
    │     ALB      │ ◄─── Path-based Routing
    │  (Multi-AZ)  │      /v1/* → LiteLLM
    └──────┬───────┘      /grafana/* → Grafana
           │              /langfuse/* → Langfuse
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
┌────────┐   ┌────────┐
│LiteLLM │   │LiteLLM │  ◄─── Round-Robin LB
│ AZ-a   │   │ AZ-b   │       Health Checks
└───┬────┘   └───┬────┘
    │            │
    └─────┬──────┘
          │
          ▼
    ┌──────────────┐
    │ AWS Bedrock  │ ◄─── IAM Role Auth
    │ (us-east-1)  │      Cross-Region OK
    └──────────────┘


                    METRICS FLOW
                    ════════════

    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │ LiteLLM  │     │ Langfuse │     │ Grafana  │
    │ /metrics │     │ /metrics │     │ (Query)  │
    └────┬─────┘     └────┬─────┘     └────┬─────┘
         │                │                │
         │ Prometheus     │                │
         │ Scrape         │                │ PromQL
         ▼                ▼                ▼
    ┌─────────────────────────────────────────────┐
    │            Victoria Metrics                 │
    │         /victoria-metrics-data              │
    │                    │                        │
    └────────────────────┼────────────────────────┘
                         │
                         ▼
    ┌─────────────────────────────────────────────┐
    │              Amazon EFS                     │
    │    (Persistent Metrics Storage - 30 days)   │
    └─────────────────────────────────────────────┘
```

---

## Service Components

### Component Sizing Matrix

| Service | CPU | Memory | Replicas | Spot | Auto-Scale |
|---------|-----|--------|----------|------|------------|
| **LiteLLM** | 2048 (2 vCPU) | 4096 MB | 2-6 | No | Yes (CPU 70%) |
| **Grafana** | 512 | 1024 MB | 2 | No | No |
| **Victoria Metrics** | 512 | 1024 MB | 1 | No | No |
| **Langfuse** | 1024 | 2048 MB | 2 | No | No |

### Service Architecture Detail

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ECS FARGATE CLUSTER                               │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    LiteLLM Service (Critical)                        │   │
│  │                                                                      │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  │   │
│  │   │   Task 1    │  │   Task 2    │  │   Task 3    │  │  Task N   │  │   │
│  │   │  2 vCPU     │  │  2 vCPU     │  │  2 vCPU     │  │ (scaled)  │  │   │
│  │   │  4 GB RAM   │  │  4 GB RAM   │  │  4 GB RAM   │  │           │  │   │
│  │   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────┬─────┘  │   │
│  │          │                │                │                │       │   │
│  │          └────────────────┴────────────────┴────────────────┘       │   │
│  │                                   │                                  │   │
│  │                    ┌──────────────▼──────────────┐                   │   │
│  │                    │   Target Group (:4000)      │                   │   │
│  │                    │   Health: /health/liveliness│                   │   │
│  │                    │   Deregistration: 30s       │                   │   │
│  │                    └─────────────────────────────┘                   │   │
│  │                                                                      │   │
│  │   Auto-Scaling Policy:                                               │   │
│  │   • Target: CPU Utilization 70%                                      │   │
│  │   • Min: 2 tasks | Max: 6 tasks                                      │   │
│  │   • Scale-out cooldown: 60s                                          │   │
│  │   • Scale-in cooldown: 300s                                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Grafana Service (Important)                       │   │
│  │                                                                      │   │
│  │   ┌─────────────┐  ┌─────────────┐                                  │   │
│  │   │   Task 1    │  │   Task 2    │   Fixed: 2 replicas              │   │
│  │   │  0.5 vCPU   │  │  0.5 vCPU   │   No auto-scaling                │   │
│  │   │  1 GB RAM   │  │  1 GB RAM   │   Stateless (provisioned config) │   │
│  │   └──────┬──────┘  └──────┬──────┘                                  │   │
│  │          │                │                                          │   │
│  │          └────────────────┘                                          │   │
│  │                  │                                                   │   │
│  │   ┌──────────────▼──────────────┐                                   │   │
│  │   │   Target Group (:3000)      │                                   │   │
│  │   │   Health: /api/health       │                                   │   │
│  │   └─────────────────────────────┘                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Langfuse Service (Important)                      │   │
│  │                                                                      │   │
│  │   ┌─────────────┐  ┌─────────────┐                                  │   │
│  │   │   Task 1    │  │   Task 2    │   Fixed: 2 replicas              │   │
│  │   │  1 vCPU     │  │  1 vCPU     │   RDS-backed (stateless app)     │   │
│  │   │  2 GB RAM   │  │  2 GB RAM   │                                  │   │
│  │   └──────┬──────┘  └──────┬──────┘                                  │   │
│  │          │                │                                          │   │
│  │          └────────────────┴──────────────────┐                      │   │
│  │                                              │                       │   │
│  │   ┌──────────────────────────┐    ┌──────────▼───────────┐          │   │
│  │   │   Target Group (:3000)   │    │   RDS PostgreSQL     │          │   │
│  │   │   Health: /api/health    │    │   (Shared Database)  │          │   │
│  │   └──────────────────────────┘    └──────────────────────┘          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                Victoria Metrics Service (Persistence)                │   │
│  │                                                                      │   │
│  │   ┌─────────────┐                                                   │   │
│  │   │   Task 1    │   Single replica (sufficient for 100 users)       │   │
│  │   │  0.5 vCPU   │   EFS-backed persistent storage                   │   │
│  │   │  1 GB RAM   │   30-day retention                                │   │
│  │   └──────┬──────┘                                                   │   │
│  │          │                                                           │   │
│  │          │ Volume Mount                                              │   │
│  │          ▼                                                           │   │
│  │   ┌──────────────────────────────────────┐                          │   │
│  │   │           Amazon EFS                 │                          │   │
│  │   │   Mount: /victoria-metrics-data      │                          │   │
│  │   │   Size: 50 GB provisioned            │                          │   │
│  │   │   Mode: Bursting throughput          │                          │   │
│  │   └──────────────────────────────────────┘                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Scaling Architecture

### LiteLLM Auto-Scaling

```
                         AUTO-SCALING BEHAVIOR
                         ═════════════════════

    Load Increase                              Load Decrease
         │                                          │
         ▼                                          ▼
    ┌─────────────┐                          ┌─────────────┐
    │ CPU > 70%   │                          │ CPU < 70%   │
    │ (Target)    │                          │ (Sustained) │
    └──────┬──────┘                          └──────┬──────┘
           │                                        │
           ▼                                        ▼
    ┌─────────────┐                          ┌─────────────┐
    │ Scale Out   │                          │ Cooldown    │
    │ +1 Task     │                          │ 300 seconds │
    └──────┬──────┘                          └──────┬──────┘
           │                                        │
           ▼                                        ▼
    ┌─────────────┐                          ┌─────────────┐
    │ Cooldown    │                          │ Scale In    │
    │ 60 seconds  │                          │ -1 Task     │
    └─────────────┘                          └─────────────┘


    SCALING TIMELINE EXAMPLE:
    ═════════════════════════

    Users    Tasks    CPU%
    ─────    ─────    ────
     10        2       30%   ◄── Baseline (min replicas)
     50        2       55%   ◄── Normal load
     80        2       72%   ◄── Threshold crossed
     80        3       48%   ◄── Task 3 launched (60s later)
    120        3       71%   ◄── Threshold crossed again
    120        4       53%   ◄── Task 4 launched
     60        4       26%   ◄── Load decreases
     60        4       26%   ◄── Cooldown period (300s)
     60        3       35%   ◄── Scale in
     30        3       17%   ◄── Load decreases
     30        2       26%   ◄── Scale in to minimum
```

### Capacity Planning

```
    CONCURRENT USER CAPACITY
    ════════════════════════

    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │  LiteLLM Task Capacity (per task):                          │
    │  • Max concurrent requests: ~50-100                         │
    │  • Avg latency: 500ms-2s (depends on model)                 │
    │  • Memory per request: ~10-50 MB                            │
    │                                                             │
    │  ┌─────────────────────────────────────────────────────┐   │
    │  │  Tasks │ Concurrent Users │ Requests/sec (est.)     │   │
    │  ├────────┼──────────────────┼─────────────────────────┤   │
    │  │   2    │      100         │        50-100           │   │
    │  │   3    │      150         │        75-150           │   │
    │  │   4    │      200         │       100-200           │   │
    │  │   5    │      250         │       125-250           │   │
    │  │   6    │      300         │       150-300           │   │
    │  └────────┴──────────────────┴─────────────────────────┘   │
    │                                                             │
    │  Bottleneck: AWS Bedrock quotas (tokens/min, requests/min)  │
    │  Monitor: litellm_proxy_total_requests_metric_total         │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
```

---

## High Availability & Reliability

### Multi-AZ Deployment

```
    AVAILABILITY ZONE DISTRIBUTION
    ══════════════════════════════

    ┌──────────────────────────────────────────────────────────────────────┐
    │                                                                      │
    │        us-east-1a              us-east-1b              us-east-1c    │
    │    ┌───────────────┐      ┌───────────────┐      ┌───────────────┐  │
    │    │               │      │               │      │               │  │
    │    │  LiteLLM (1)  │      │  LiteLLM (1)  │      │  (overflow)   │  │
    │    │  Grafana (1)  │      │  Grafana (1)  │      │               │  │
    │    │  Langfuse (1) │      │  Langfuse (1) │      │               │  │
    │    │  Victoria (1) │      │               │      │               │  │
    │    │               │      │               │      │               │  │
    │    │  RDS Primary  │      │  RDS Standby  │      │               │  │
    │    │  EFS Mount    │      │  EFS Mount    │      │  EFS Mount    │  │
    │    │               │      │               │      │               │  │
    │    └───────────────┘      └───────────────┘      └───────────────┘  │
    │                                                                      │
    └──────────────────────────────────────────────────────────────────────┘

    FAILURE SCENARIOS:
    ══════════════════

    Scenario 1: Single AZ Failure (us-east-1a down)
    ────────────────────────────────────────────────
    • LiteLLM: 1/2 tasks remain → Service continues (50% capacity)
    • Grafana: 1/2 tasks remain → Dashboards accessible
    • Langfuse: 1/2 tasks remain → Tracing continues
    • Victoria: Task fails → ECS reschedules to us-east-1b (brief gap)
    • RDS: Auto-failover to Standby (60-120s)
    • Impact: Temporary degraded performance, no data loss

    Scenario 2: Task Crash (OOM, Bug)
    ─────────────────────────────────
    • ECS automatically restarts task
    • ALB health check detects failure (30s)
    • Traffic routed to healthy tasks
    • Impact: None (if multiple replicas)

    Scenario 3: Database Failure
    ────────────────────────────
    • RDS Multi-AZ: Automatic failover (60-120s)
    • LiteLLM: Retries DB connections
    • Langfuse: Retries DB connections
    • Impact: Brief write failures, automatic recovery
```

### Recovery Time Objectives

| Component | RTO | RPO | Recovery Method |
|-----------|-----|-----|-----------------|
| LiteLLM | < 30s | N/A (stateless) | ALB health check + new task |
| Grafana | < 30s | N/A (stateless) | ALB health check + new task |
| Langfuse | < 30s | 0 (RDS-backed) | ALB health check + new task |
| Victoria Metrics | < 2min | < 15s (scrape interval) | ECS restart + EFS mount |
| RDS PostgreSQL | < 2min | 0 (synchronous replication) | Multi-AZ automatic failover |

### Health Checks

```
    HEALTH CHECK CONFIGURATION
    ══════════════════════════

    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │  Service        │ Endpoint              │ Interval │ Timeout │ Threshold
    │  ────────────── │ ───────────────────── │ ──────── │ ─────── │ ─────────
    │  LiteLLM        │ /health/liveliness    │    30s   │   5s    │ 3 unhealthy
    │  Grafana        │ /api/health           │    30s   │   5s    │ 3 unhealthy
    │  Langfuse       │ /api/health           │    30s   │   5s    │ 3 unhealthy
    │  Victoria       │ /-/healthy            │    30s   │   5s    │ 3 unhealthy
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘

    STARTUP GRACE PERIODS:
    ──────────────────────
    • LiteLLM: 90 seconds (DB migrations, config loading)
    • Grafana: 60 seconds (dashboard provisioning)
    • Langfuse: 60 seconds (DB migrations)
    • Victoria: 30 seconds (fast startup)
```

---

## Security Architecture

### WAF Configuration

```
    WAF RULE EVALUATION ORDER
    ═════════════════════════

    Request → ┌─────────────────────────────────────────────────────────────┐
              │                                                             │
              │  Rule 1: AWS-AWSManagedRulesAmazonIpReputationList          │
              │  • Blocks known malicious IPs                               │
              │  • Action: BLOCK                                            │
              │  Priority: 1                                                │
              │                                                             │
              ├─────────────────────────────────────────────────────────────┤
              │                                                             │
              │  Rule 2: AWS-AWSManagedRulesCommonRuleSet                   │
              │  • OWASP Top 10 protection                                  │
              │  • SQL injection, XSS, path traversal                       │
              │  • Action: BLOCK                                            │
              │  Priority: 2                                                │
              │                                                             │
              ├─────────────────────────────────────────────────────────────┤
              │                                                             │
              │  Rule 3: AWS-AWSManagedRulesKnownBadInputsRuleSet           │
              │  • Log4j, Java deserialization                              │
              │  • Action: BLOCK                                            │
              │  Priority: 3                                                │
              │                                                             │
              ├─────────────────────────────────────────────────────────────┤
              │                                                             │
              │  Rule 4: AWS-AWSManagedRulesBotControlRuleSet               │
              │  • Bot detection and mitigation                             │
              │  • Verified bots: ALLOW                                     │
              │  • Malicious bots: BLOCK                                    │
              │  Priority: 4                                                │
              │                                                             │
              ├─────────────────────────────────────────────────────────────┤
              │                                                             │
              │  Rule 5: Rate Limiting                                      │
              │  • 1000 requests per 5 minutes per IP                       │
              │  • Action: BLOCK (temporary)                                │
              │  Priority: 5                                                │
              │                                                             │
              └─────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
                               ┌─────────────────┐
                               │  Default: ALLOW │
                               └─────────────────┘
```

### Secrets Management

```
    AWS SECRETS MANAGER
    ═══════════════════

    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │  Secret Name                              │ Used By                 │
    │  ──────────────────────────────────────── │ ─────────────────────── │
    │  stargate-sandbox/litellm-master-key      │ LiteLLM API auth        │
    │  stargate-sandbox/grafana-admin-password  │ Grafana admin login     │
    │  stargate-sandbox/admin-header-secret     │ CloudFront admin auth   │
    │  stargate-sandbox/langfuse-public-key     │ Langfuse client SDK     │
    │  stargate-sandbox/langfuse-secret-key     │ Langfuse client SDK     │
    │  stargate-sandbox/langfuse-nextauth-secret│ Langfuse session        │
    │  stargate-sandbox/langfuse-salt           │ Langfuse encryption     │
    │                                                                     │
    │  RDS Credentials: Auto-generated, stored in Secrets Manager         │
    │  Database URL: Composed from RDS secrets at runtime                 │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘

    ACCESS PATTERN:
    ───────────────
    ECS Task → IAM Role → Secrets Manager → Secret Value
                          (GetSecretValue)
```

---

## Data Persistence

### Storage Architecture

```
    DATA PERSISTENCE LAYERS
    ═══════════════════════

    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │  LAYER 1: Ephemeral (Container-local)                               │
    │  ────────────────────────────────────                               │
    │  • LiteLLM request cache                                            │
    │  • Grafana session data                                             │
    │  • Log buffers                                                      │
    │  • Lost on container restart                                        │
    │                                                                     │
    ├─────────────────────────────────────────────────────────────────────┤
    │                                                                     │
    │  LAYER 2: EFS (Persistent, Multi-AZ)                                │
    │  ──────────────────────────────────                                 │
    │  • Victoria Metrics time-series data                                │
    │  • 30-day retention                                                 │
    │  • Survives container restarts                                      │
    │  • Automatic backup (AWS Backup)                                    │
    │                                                                     │
    │  ┌───────────────────────────────────────────────────────────────┐  │
    │  │  EFS File System: stargate-sandbox-victoria-metrics           │  │
    │  │  ├── /victoria-metrics-data/                                  │  │
    │  │  │   ├── data/                    (TSDB blocks)               │  │
    │  │  │   ├── indexdb/                 (Inverted index)            │  │
    │  │  │   └── snapshots/               (Automatic snapshots)       │  │
    │  │  │                                                            │  │
    │  │  Throughput Mode: Bursting                                    │  │
    │  │  Performance Mode: General Purpose                            │  │
    │  │  Encryption: AES-256 (at rest)                                │  │
    │  └───────────────────────────────────────────────────────────────┘  │
    │                                                                     │
    ├─────────────────────────────────────────────────────────────────────┤
    │                                                                     │
    │  LAYER 3: RDS PostgreSQL (Persistent, Multi-AZ)                     │
    │  ───────────────────────────────────────────────                    │
    │  • LiteLLM configuration, users, keys                               │
    │  • Langfuse traces, observations, scores                            │
    │  • 7-day automated backups                                          │
    │  • Point-in-time recovery                                           │
    │                                                                     │
    │  ┌───────────────────────────────────────────────────────────────┐  │
    │  │  Database: stargate-sandbox                                   │  │
    │  │  ├── litellm schema                                           │  │
    │  │  │   ├── users                                                │  │
    │  │  │   ├── keys                                                 │  │
    │  │  │   ├── spend_logs                                           │  │
    │  │  │   └── config                                               │  │
    │  │  │                                                            │  │
    │  │  └── langfuse schema                                          │  │
    │  │      ├── traces                                               │  │
    │  │      ├── observations                                         │  │
    │  │      ├── scores                                               │  │
    │  │      └── projects                                             │  │
    │  │                                                               │  │
    │  │  Storage: 100 GB GP3 (auto-expand to 200 GB)                  │  │
    │  │  IOPS: 3000 baseline                                          │  │
    │  │  Encryption: AES-256 (at rest)                                │  │
    │  └───────────────────────────────────────────────────────────────┘  │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘
```

---

## Monitoring & Observability

### Metrics Collection

```
    OBSERVABILITY PIPELINE
    ══════════════════════

    ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
    │   LiteLLM    │     │   Langfuse   │     │   AWS ECS    │
    │   /metrics   │     │   /metrics   │     │ CloudWatch   │
    └──────┬───────┘     └──────┬───────┘     └──────┬───────┘
           │ :8000              │ :3000              │
           │                    │                    │
           └────────────────────┴────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   Victoria Metrics  │
                    │   (Scrape: 15s)     │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │    Grafana          │
                    │   ┌──────────────┐  │
                    │   │ Dashboards:  │  │
                    │   │ • LLM Usage  │  │
                    │   │ • Infra      │  │
                    │   │ • Overview   │  │
                    │   └──────────────┘  │
                    └─────────────────────┘


    KEY METRICS TO MONITOR:
    ═══════════════════════

    Business Metrics (LiteLLM):
    ──────────────────────────
    • litellm_proxy_total_requests_metric_total
    • litellm_total_tokens_metric_total (input/output)
    • litellm_spend_metric_total (USD)
    • litellm_llm_api_latency_metric_bucket

    Infrastructure Metrics (ECS):
    ─────────────────────────────
    • CPUUtilization
    • MemoryUtilization
    • RunningTaskCount
    • PendingTaskCount

    Application Metrics:
    ────────────────────
    • HTTP 4xx/5xx error rates
    • Request latency percentiles (p50, p95, p99)
    • Active connections
```

### Alert Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| LiteLLM CPU | > 60% | > 80% | Scale out |
| LiteLLM Memory | > 70% | > 85% | Investigate leaks |
| Error Rate (5xx) | > 1% | > 5% | Page on-call |
| Latency P99 | > 5s | > 10s | Check Bedrock quotas |
| RDS CPU | > 70% | > 85% | Scale up instance |
| RDS Connections | > 80% | > 90% | Connection pooling |

---

## Cost Analysis

### Monthly Cost Breakdown

```
    SANDBOX ENVIRONMENT COST ESTIMATE (us-east-1)
    ═════════════════════════════════════════════

    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │  COMPUTE (ECS Fargate)                                              │
    │  ─────────────────────                                              │
    │                                                                     │
    │  LiteLLM (2 tasks × 2 vCPU × 4 GB)                                  │
    │  └── 2 × $0.04048/hr × 730 hrs = $59.10                            │
    │  └── Memory: 2 × 8 GB × $0.004445/GB-hr × 730 = $51.87             │
    │  └── Subtotal: ~$120/month                                          │
    │                                                                     │
    │  Grafana (2 tasks × 0.5 vCPU × 1 GB)                                │
    │  └── ~$30/month                                                     │
    │                                                                     │
    │  Victoria Metrics (1 task × 0.5 vCPU × 1 GB)                        │
    │  └── ~$15/month                                                     │
    │                                                                     │
    │  Langfuse (2 tasks × 1 vCPU × 2 GB)                                 │
    │  └── ~$60/month                                                     │
    │                                                                     │
    │  ═══════════════════════════════════════════                        │
    │  Compute Subtotal: ~$225/month                                      │
    │                                                                     │
    ├─────────────────────────────────────────────────────────────────────┤
    │                                                                     │
    │  DATABASE (RDS PostgreSQL)                                          │
    │  ──────────────────────────                                         │
    │                                                                     │
    │  db.r6g.large Multi-AZ                                              │
    │  └── $0.252/hr × 730 hrs = $184/month                              │
    │                                                                     │
    │  Storage (100 GB GP3)                                               │
    │  └── $0.115/GB × 100 GB = $11.50/month                             │
    │                                                                     │
    │  ═══════════════════════════════════════════                        │
    │  Database Subtotal: ~$195/month                                     │
    │                                                                     │
    ├─────────────────────────────────────────────────────────────────────┤
    │                                                                     │
    │  NETWORKING                                                         │
    │  ──────────                                                         │
    │                                                                     │
    │  NAT Gateway                                                        │
    │  └── $0.045/hr × 730 hrs = $32.85/month                            │
    │  └── Data processing: ~$5/month (estimate)                          │
    │                                                                     │
    │  CloudFront                                                         │
    │  └── ~$5/month (low traffic estimate)                               │
    │                                                                     │
    │  ═══════════════════════════════════════════                        │
    │  Networking Subtotal: ~$43/month                                    │
    │                                                                     │
    ├─────────────────────────────────────────────────────────────────────┤
    │                                                                     │
    │  STORAGE & SECURITY                                                 │
    │  ──────────────────                                                 │
    │                                                                     │
    │  EFS (50 GB)                                                        │
    │  └── $0.30/GB × 50 GB = $15/month                                  │
    │                                                                     │
    │  WAF (Advanced with Bot Control)                                    │
    │  └── $5 base + $10 Bot Control = $15/month                         │
    │                                                                     │
    │  ═══════════════════════════════════════════                        │
    │  Storage & Security Subtotal: ~$30/month                            │
    │                                                                     │
    ├─────────────────────────────────────────────────────────────────────┤
    │                                                                     │
    │  ╔═══════════════════════════════════════════════════════════════╗  │
    │  ║  TOTAL FIXED INFRASTRUCTURE: ~$493/month                      ║  │
    │  ╚═══════════════════════════════════════════════════════════════╝  │
    │                                                                     │
    │  Variable Costs (Pay-per-use):                                      │
    │  • AWS Bedrock: Based on token consumption                          │
    │  • Data transfer: Based on API response sizes                       │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘
```

---

## Comparison: POC vs Sandbox

| Aspect | POC | Sandbox |
|--------|-----|---------|
| **Region** | us-west-1 | us-east-1 |
| **Availability Zones** | 2 | 3 |
| **LiteLLM Replicas** | 1 | 2-6 (auto-scale) |
| **Grafana Replicas** | 1 | 2 |
| **Langfuse Replicas** | 1 | 2 |
| **Victoria Metrics** | Ephemeral | EFS-persistent |
| **RDS Instance** | db.t4g.micro | db.r6g.large |
| **RDS Multi-AZ** | No | Yes |
| **NAT** | t3.nano instance | NAT Gateway |
| **WAF** | Disabled | Advanced (Bot Control) |
| **Secrets** | Shared | Dedicated (isolated) |
| **Spot Instances** | Yes | No |
| **Monthly Cost** | ~$50 | ~$493 |
| **Target Users** | Development | 100 concurrent |

---

## Deployment Checklist

### Pre-Deployment

- [ ] Create secrets in AWS Secrets Manager (us-east-1)
- [ ] Request Bedrock model access in us-east-1
- [ ] Create S3 bucket for Terraform state
- [ ] Validate IAM permissions

### Deployment

- [ ] `terraform init` - Initialize providers
- [ ] `terraform plan` - Review changes
- [ ] `terraform apply` - Deploy infrastructure
- [ ] Verify ECS services healthy
- [ ] Test CloudFront endpoints

### Post-Deployment Validation

- [ ] LiteLLM health: `curl https://<domain>/health/liveliness`
- [ ] Grafana access: `https://<domain>/grafana`
- [ ] Langfuse access: `https://<domain>/langfuse`
- [ ] Metrics flowing to Victoria Metrics
- [ ] WAF blocking test (rate limit)

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-25 | Architecture Team | Initial document |
