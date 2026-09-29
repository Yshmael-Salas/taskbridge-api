# Architecture: TaskBridge API (Summary)

## Service Integration
Project Service (source of truth) owns milestone state mutations and business logic. Notification & Audit Service (downstream consumer) listens to domain events asynchronously and handles audit persistence and notification dispatch. Project Service does not depend on or call Notification Service; it publishes a MILESTONE_REOPENED event with event_id (dedup), correlation_id (tracing), actor_id, actor_ip_hash (encrypted), and status transition details.

## Data Flow
Inbound API request → authenticate & extract tenant_id → validate milestone reopen business rules → update milestone state in transaction → emit audit_log entry and milestone_event entry (within same transaction) → publish async event to queue (Project Service returns immediately) → Notification & Audit consumer dequeues, deduplicates by event_id, persists notification queue entry, retries on failure. Result: milestone state is immediately durable; notifications are eventually consistent.

## B2B SaaS Appropriateness
This architecture enforces multi-tenant isolation at the database level (RLS policies prevent cross-tenant leakage), provides immutable audit trails for compliance and forensic investigation, isolates notification failures from core business logic (milestone change succeeds even if email fails), and allows independent scaling of Project and Notification services. These properties are essential for regulated industries and high-reliability requirements.

## Design Decisions & Trade-Offs
**(1) Async event-driven vs. synchronous RPC:** Chose async to keep milestone mutation fast (100ms) and isolated from notification latency (1-5s); rejected sync RPC because notification failures would block user operations. **(2) Full IP + encryption vs. IP hashing vs. no IP:** Chose encryption for forensic capability while maintaining GDPR compliance via retention policy and RLS; rejected IP-only hashing because forensic investigation requires actual IPs. **(3) Append-only immutable audit log vs. mutable vs. fully deletable:** Chose immutable with 90-day IP retention + indefinite anonymized events to prevent tampering, balance privacy compliance (Right to Erasure), and enable breach investigation. **(4) Durable queue with idempotent consumers vs. fire-and-forget:** Chose durable queue because one duplicate notification is better than a missing one; fire-and-forget loses visibility and reliability.

