# Milkful — Well-Architected Re-Architecture (HLD & LLD)

This document re-architects the Milkful platform to follow the **AWS Well-Architected
Framework** and modern cloud-native patterns. It complements `milkful-system-design.md`
and is the authoritative reference for the updated diagrams.

Importable diagrams:

- `docs/design/milkful-hld.drawio` — 2 pages: **Well-Architected Architecture (VPC + Zero-Trust + Stateless)** and **Database-per-Service**
- `docs/design/milkful-messaging.drawio` — **Event-driven messaging topology** (who publishes/consumes which EventBridge event, SQS queue, SNS topic, Step Functions workflow)
- `docs/design/milkful-lld.drawio` — LLD sequence flows (now showing EventBridge → SQS → consumer)

---

## 1. Key Architectural Decisions

| Concern | Decision |
|---------|----------|
| **Networking** | All compute and data live inside a **VPC** across **≥2 Availability Zones**, in **private subnets**. Only the ALB and NAT Gateway sit in public subnets. |
| **Trust model** | **Zero-Trust**: authenticate & authorize *every* request; default-deny security groups; private subnets; **VPC endpoints (PrivateLink)** so AWS-service traffic never leaves the VPC; least-privilege IAM role per service; mTLS between services. |
| **Statelessness** | Services keep **no local session state**. Identity travels in a **JWT**; shared state (cart, sessions, tracking) is externalized to **Redis / DynamoDB**. Any instance can serve any request → free horizontal scaling. |
| **Data ownership** | **Database-per-service** — each microservice owns its datastore. No service reads another service's database. Cross-service data flows via **events or APIs** only. |
| **Integration** | **Event-driven**: services publish domain events to a central **EventBridge** bus; rules route to **per-consumer SQS queues (each with a DLQ)**; consumers poll their own queue. **SNS** does last-mile notification fan-out. **Step Functions** orchestrate multi-step **sagas**. |
| **Resilience** | Multi-AZ, auto-scaling, DLQs, retries with backoff, idempotency, circuit breakers, and saga-based compensation. |

---

## 2. AWS Well-Architected Framework Alignment

### 2.1 Operational Excellence
- Infrastructure as Code (CDK/Terraform), CI/CD (CodePipeline / GitHub Actions), blue/green deploys.
- Centralized observability: **CloudWatch** metrics/logs/alarms, **X-Ray** distributed tracing, **CloudTrail** audit.
- Runbooks + automated rollback; every event carries a correlation ID end-to-end.

### 2.2 Security (Zero-Trust)
- **Authenticate every request**: Cognito-issued JWT verified at API Gateway; **SigV4/IAM or mTLS** for service-to-service.
- **Least privilege**: one IAM role per service/task; scoped policies; no broad `*` permissions.
- **Network**: private subnets, default-deny security groups, **VPC endpoints** for SQS/SNS/EventBridge/S3/DynamoDB/Secrets Manager/KMS (no public egress for AWS APIs).
- **Data protection**: TLS 1.2+ in transit; **KMS** encryption at rest everywhere; **Secrets Manager** with rotation.
- **Detection**: GuardDuty, Security Hub, WAF + Shield at the edge.

### 2.3 Reliability
- Multi-AZ for compute, Aurora, ElastiCache, and NAT.
- **Async decoupling with SQS** absorbs spikes (6 AM subscription burst); **DLQs** isolate poison messages.
- Idempotency keys; **saga pattern** (Step Functions) with compensating transactions; automated backups + PITR; cross-region DR.

### 2.4 Performance Efficiency
- **Hybrid compute** (see §6.1): **Lambda** (5 services) for spiky/event work with scale-to-zero; **ECS Fargate** (8 services) behind the ALB for steady, low-latency, long-lived-connection workloads.
- **ElastiCache Redis** for hot reads; **CloudFront** edge caching; **OpenSearch** for search; DynamoDB single-digit-ms.
- Right-sized Aurora Serverless v2 with read replicas.

### 2.5 Cost Optimization
- Pay-per-use (Lambda, DynamoDB on-demand, Aurora Serverless v2, SQS/EventBridge).
- Pre-generate subscription orders off-peak to flatten load; S3 lifecycle policies; VPC endpoints reduce NAT data cost.

### 2.6 Sustainability
- Serverless + auto-scaling minimize idle capacity; Graviton (ARM) for Fargate/Lambda; efficient batching of the daily run.

---

## 3. Modern Architecture Patterns Used

| Pattern | Where |
|---------|-------|
| **Database-per-Service** | Every microservice owns its datastore (see §6). |
| **Event-Driven Architecture** | EventBridge domain-event bus. |
| **Queue-based Load Leveling** | SQS queue (with DLQ) per consumer. |
| **Publish/Subscribe fan-out** | SNS topics for SMS/push/email + OTP. |
| **Saga / Orchestration** | Step Functions for Order Saga, Subscription Daily Run, Refund. |
| **Transactional Outbox** | Reliable event publishing from each service DB. |
| **CQRS** | Reporting service reads from OpenSearch/data-lake projections, not OLTP DBs. |
| **BFF / API Gateway** | Single authenticated edge for apps. |
| **Circuit Breaker + Retry/Backoff** | Around external calls (Razorpay, Location). |
| **Idempotent Consumer** | Dedupe on message/idempotency key. |
| **Strangler Fig** | Incremental migration from the 2-Lambda MVP to full services. |

---

## 4. VPC & Network Design (Zero-Trust)

```
Amazon VPC (10.0.0.0/16, multi-AZ)
├─ Public Subnets (AZ-a, AZ-b)
│   ├─ Application Load Balancer (TLS termination)
│   └─ NAT Gateway (controlled egress to external APIs)
├─ Private App Subnets (AZ-a, AZ-b)
│   └─ Microservices (stateless, IAM role per service):
│       ECS Fargate x8 (behind ALB) + Lambda x5 (event-driven)
├─ Private Data Subnets (AZ-a, AZ-b)
│   └─ Per-service databases: Aurora clusters, ElastiCache, OpenSearch
└─ VPC Endpoints (PrivateLink): SQS, SNS, EventBridge, S3, DynamoDB,
   Secrets Manager, KMS, CloudWatch  (AWS traffic stays private)
```

- **Default-deny** security groups; each service SG allows only required ports from specific SGs.
- **No database is publicly reachable**; app tier reaches data tier only via SG rules.
- **VPC endpoints** keep SQS/SNS/EventBridge/S3/DynamoDB traffic off the public internet.
- External calls (Razorpay, WhatsApp) egress **only** via the NAT Gateway.

---

## 5. Stateless Service Design

- **No sticky sessions / no server-side session store** in the service instances.
- **JWT** (Cognito) carries identity & roles; verified per request.
- **Externalized state**: cart & live tracking → DynamoDB; hot cache & rate limits → Redis; files → S3.
- **Idempotency keys** on writes (orders, payments) so retries are safe.
- Result: any instance can handle any request → **horizontal auto-scaling** across AZs with no affinity.

---

## 6. Database-per-Service (no shared database)

| Service | Compute | Owns (private datastore) |
|---------|---------|--------------------------|
| Identity & Auth | **Lambda** | Amazon Cognito (user pool) |
| User Service | **Lambda** | Aurora PostgreSQL — `users` cluster |
| Catalog Service | **Fargate** | Aurora — `catalog` cluster **+** OpenSearch index |
| Inventory Service | **Fargate** | Aurora — `inventory` cluster |
| Cart Service | **Lambda** | DynamoDB — `cart` table (TTL) |
| Order Service | **Fargate** | Aurora — `orders` cluster |
| Subscription Service | **Lambda** | Aurora — `subscriptions` cluster |
| Payment Service | **Fargate** | Aurora — `payments` cluster |
| Wallet Service | **Fargate** | Aurora — `wallet` cluster (ledger) |
| Pricing & Offer Service | **Fargate** | Aurora — `offers` cluster **+** Redis |
| Delivery Service | **Fargate** | Aurora — `delivery` cluster **+** DynamoDB (live tracking) |
| Notification Service | **Lambda** | DynamoDB — `templates`/`logs` |
| Reporting & Analytics | **Fargate** | OpenSearch + S3 data lake (CQRS read models) |

> Rule: a service **never** connects to another service's database. It gets the data it needs
> by subscribing to events (eventual consistency) or calling the owning service's API.

### 6.1 Hybrid compute — why Lambda vs Fargate

The platform uses **both** compute models; each service picks the one that fits its runtime profile. The event-driven design means a service can switch compute type later without changing its interfaces.

**Lambda (5)** — event-driven, bursty, scale-to-zero glue; invoked directly by API Gateway / EventBridge:
`Identity & Auth`, `User`, `Cart`, `Subscription` (EventBridge-Scheduler daily run), `Notification`.

**ECS Fargate (8)** — always-on, latency-sensitive, long-lived connections, steady throughput; sit behind the internal ALB:
`Catalog`, `Pricing & Offer`, `Order`, `Payment`, `Wallet`, `Inventory`, `Delivery`, `Reporting & Analytics`.

Rationale for keeping the heavy services on Fargate: Lambda's **15-minute limit** (Reporting batch), **cold starts** on hot paths (Catalog, Pricing), **no long-lived connections / WebSockets** (Delivery tracking), **DB connection storms** against Aurora (Order/Payment/Wallet/Inventory — mitigated further with RDS Proxy), and **cost inversion** under sustained load at Regional scale. Lambda stays for spiky, short, event-triggered work where scale-to-zero wins.

---

## 7. Event-Driven Messaging Topology

### 7.1 Domain events on the EventBridge bus (`milkful-events`)

| Event | Producer |
|-------|----------|
| `OrderPlaced`, `OrderConfirmed`, `OrderCancelled` | Order Service |
| `PaymentConfirmed`, `PaymentFailed` | Payment Service |
| `StockChanged`, `LowStock` | Inventory Service |
| `SubscriptionOrderDue` | Subscription Service (via Step Functions) |
| `DeliveryStatusChanged` | Delivery Service |
| `UserRegistered` | User Service |
| `WalletLowBalance` | Wallet Service |

### 7.2 EventBridge rules → SQS queue (with DLQ) → consumer

| SQS Queue (+ DLQ) | Consumer Service | Triggering events (rule) |
|-------------------|------------------|--------------------------|
| `order-events-q` | Order Service | PaymentConfirmed, PaymentFailed, SubscriptionOrderDue |
| `inventory-events-q` | Inventory Service | OrderCancelled (release stock) |
| `catalog-events-q` | Catalog Service | StockChanged (refresh availability) |
| `wallet-events-q` | Wallet Service | UserRegistered (auto-create), OrderConfirmed (ledger), OrderCancelled (refund) |
| `delivery-events-q` | Delivery Service | OrderConfirmed (assign delivery) |
| `notification-events-q` | Notification Service | OrderConfirmed, OrderCancelled, PaymentFailed, DeliveryStatusChanged, LowStock, WalletLowBalance, UserRegistered |
| `reporting-events-q` | Reporting Service | all events (catch-all rule) |

Each queue has a **redrive policy** to a dedicated **DLQ**; consumers are **idempotent** and use long-polling with visibility-timeout tuned to processing time.

### 7.3 SNS topics (last-mile fan-out)

| SNS Topic | Publisher | Subscribers / delivery |
|-----------|-----------|------------------------|
| `sns-sms` | Notification Service, Auth (OTP) | SMS / WhatsApp provider |
| `sns-push` | Notification Service | Amazon Pinpoint (push) |
| (email) | Notification Service | Amazon SES |

### 7.4 Step Functions (orchestration / saga)

| Workflow | Trigger | Orchestrates |
|----------|---------|--------------|
| **Order Saga** | Order Service on checkout | Reserve (Inventory) → Charge (Payment/Wallet) → Confirm (Order); **compensate** on failure (release stock, refund) |
| **Subscription Daily Run** | EventBridge Scheduler (pre-cutoff) | Get due (Subscription) → Create orders (Order) → Auto-debit (Wallet) → Notify |
| **Refund Workflow** | Order/Payment on cancellation | Wallet refund + gateway refund + Notification |

---

## 8. Diagram index

| File / Page | Shows |
|-------------|-------|
| `milkful-hld.drawio` → *Architecture* | VPC, public/private subnets, edge, app tier (stateless), data tier, messaging backbone, VPC endpoints, zero-trust/observability, external egress via NAT |
| `milkful-hld.drawio` → *Database-per-Service* | Each of the 13 services with its own dedicated datastore |
| `milkful-messaging.drawio` | Producers → EventBridge → per-consumer SQS (+DLQ) → consumers; SNS fan-out; Step Functions sagas |
| `milkful-lld.drawio` | Order / Subscription / Inventory / Delivery flows with EventBridge → SQS → consumer |

Open in [app.diagrams.net](https://app.diagrams.net) → **File → Open From → Device**.
