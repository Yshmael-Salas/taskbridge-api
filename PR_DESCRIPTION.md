# PR Description

## Summary of What Was Built and Why

This change introduces a Notification & Audit capability for project milestone lifecycle events, with the initial trigger being milestone reopen operations. The goal is to provide stronger operational visibility, better accountability, and event-driven downstream notifications without coupling the core project workflow directly to notification delivery.

### What was built
- A new milestone event model for lifecycle transitions
- A reusable audit log path for actor identity and event metadata
- A notification queue contract for downstream consumers
- A milestone reopen workflow that emits a structured event and writes audit records
- A minimal set of service integration points between the project domain and the notification/audit domain

### Why it was built
- To ensure milestone state changes are traceable for internal operations and support investigations
- To notify relevant stakeholders when a milestone is reopened, reducing visibility gaps
- To decouple project mutation logic from notification delivery and reduce cross-service coordination in app code
- To set up a common pattern for future audit-enabled events beyond milestone reopen

### Domain behavior
When a milestone is reopened, the workflow now:
1. Updates milestone state from completed or closed to reopened
2. Persists an audit record describing who changed it and when
3. Emits a domain event such as `MILESTONE_REOPENED`
4. Queues a notification for configured subscribers or downstream services

---

## AI Tool Disclosure

### Tools used
- GitHub Copilot Chat for architecture and review guidance
- GitHub Copilot inline code generation for SQL/service scaffolding and test cases
- GitHub Copilot test generation assistance for unit/integration coverage
- GitHub Copilot PR summary and review hint generation

### Where AI output was accepted
- Generated the initial SQL service and event schema skeletons
- Suggested common audit log field naming and event payload conventions
- Drafted the first version of test cases and negative tests
- Helped define the notification queue contract and event payload structure

### Where AI output was overridden or manually corrected
- I changed the audit record design to include explicit privacy and retention controls for actor IP data rather than accepting a raw log-only approach
- I revised the integration contract to emphasize idempotency, correlation IDs, and event-sequencing assumptions rather than relying on a simplistic fire-and-forget event model
- I tightened validation rules around status transitions and business constraints instead of accepting the AI-generated permissive workflow
- I removed assumptions that all downstream consumers can safely process events without retry or acknowledgment semantics

### AI-generated vs hand-written estimate
- Estimated AI-generated code: 35%
- Estimated hand-written/manual code: 65%

Reasoning:
- The service contracts, schema constraints, and status transition logic were mostly shaped by manual review and domain validation
- AI accelerated the bootstrap and boilerplate but the final design was manually tightened for correctness, privacy, and operational safety

---

## How the Services Integrate

This feature spans two main service domains:

### 1) Project Service
Responsible for:
- milestone state updates
- validating business rules
- persisting the updated project/milestone record
- invoking the audit/event emission step

### 2) Notification & Audit Service
Responsible for:
- writing audit entries
- persisting domain events or notification jobs
- sending or dispatching notifications to subscribed channels
- ensuring idempotent processing and traceability

### Integration pattern
The project service does not call downstream notification channels directly. Instead, it emits a domain event contract that the Notification & Audit service consumes.

### Proposed contract
Event name:
- `MILESTONE_REOPENED`

Event payload:
```json
{
  "event_id": "uuid",
  "event_type": "MILESTONE_REOPENED",
  "source_service": "project-service",
  "correlation_id": "uuid",
  "actor_id": "uuid",
  "actor_ip_hash": "string",
  "project_id": "uuid",
  "milestone_id": "uuid",
  "status_before": "completed",
  "status_after": "reopened",
  "occurred_at": "2026-09-29T12:30:00Z",
  "metadata": {
    "reason": "manual-reopen",
    "request_id": "uuid"
  }
}
```

### Inter-service contracts established
- Event contract is versioned and includes an event identifier and correlation ID
- Notification & Audit service acknowledges receipt and stores an immutable event record
- Notification consumers must be idempotent and tolerant of retries
- Audit records are separate from notification delivery records so failures in one channel do not invalidate the other
- The actor IP is treated as sensitive metadata and not exposed broadly in notification payloads

### Dependencies and assumptions
- The project service is the source of truth for milestone state transitions
- Notification & Audit service is a downstream consumer, not the system of record for milestone data
- Event delivery is asynchronous but should be at-least-once with dedupe semantics

---

## Testing Coverage and Known Gaps

### Covered
- Unit tests for milestone reopen validation logic
- Unit tests for audit payload generation and required fields
- Unit tests for notification queue creation and dedupe logic
- Database tests for milestone status transitions and constraints
- Integration tests for the project-to-audit-event workflow
- Negative tests for invalid status transition attempts
- Security-oriented tests for actor IP masking or hashing handling

### Known gaps
- No full end-to-end load test for high-volume milestone events yet
- No production-like retry storm simulation for notification consumers
- No explicit contract consumer tests for third-party notification integrations
- No long-term retention and purge validation for sensitive audit data in production environments
- No multi-region or failover testing for the event pipeline

### Testing status summary
- Core service path: covered
- Event contract correctness: partially covered
- Resilience/retry semantics: not yet fully covered
- Privacy-sensitive audit storage: covered at the schema and validation layer, but not fully load-tested in production-like conditions

---

## Risk / Trade-off in the Multi-Service Design

One genuine risk in this design is the gap between eventual consistency and operational correctness.

### Risk
The project service may update the milestone and emit the event successfully, but the notification or audit consumer may lag, fail, or process the same event twice. If the system relies on immediate downstream completion for business correctness, there is a risk of inconsistent visibility or duplicate notifications.

### Trade-off
We chose a decoupled event-driven pattern to keep the project domain clean and reduce direct dependencies, but this adds:
- delayed consistency
- retry complexity
- extra observability requirements
- more surface area for partial failure

This is a reasonable trade-off for auditability and extensibility, but it means we must invest in idempotency, retry-safe contracts, and durable message processing to keep the design operationally safe.

---

## Self-Review Checklist Ran Before Submitting

- [ ] Confirmed that milestone reopen logic preserves domain invariants
- [ ] Verified audit payload contains actor identity and relevant event metadata
- [ ] Confirmed notification event is emitted only after successful state mutation
- [ ] Reviewed whether status transitions are validated consistently
- [ ] Reviewed event payload for privacy-sensitive data and ensured IP is minimized
- [ ] Confirmed idempotency and retry behavior are considered for downstream consumers
- [ ] Reviewed schema and field naming for consistency across services
- [ ] Verified there are no direct notification side effects in core project logic
- [ ] Checked for backward compatibility of event schema and versioning strategy
- [ ] Confirmed tests cover happy path, edge cases, and negative path
- [ ] Reviewed logs and error handling to avoid leaking personal data
- [ ] Confirmed retention and access controls are accounted for in the design

---

## Peer Review Simulation

### Review Comment 1
**Reviewer:** @teammateA  
**Location:** `src/notifications/service.sql` — `queue_notification_for_event()`  
**Comment:** The notification queue job currently appears to fire immediately after the domain event is accepted, without a retry/acknowledgement contract. This makes the system vulnerable to dropped notifications if the queue consumer is slow or the process crashes after enqueueing but before delivery. Please add a contract-level retry policy and idempotency key (for example, one based on `event_id`) before merging. This is important because the reopen event is operationally visible and duplicate notifications would be misleading for stakeholders.  

### Review Comment 2
**Reviewer:** @teammateB  
**Location:** `src/audit/model.sql` — `audit_logs.actor_ip_address`  
**Comment:** I’m concerned that we are storing IP data in the same table and same access model as general audit records. If this table is exposed to broad read access, the entire audit surface becomes a privacy hotspot. Please separate the sensitive IP-bearing fields behind a restricted access path or encrypted column strategy, and ensure the default consumers see a masked or hashed version. This is not just a storage concern; it changes the blast radius of a breach and is something AI-generated scaffolds often overlook because they focus on functionality rather than least-privilege data handling.  

### Review Comment 3
**Reviewer:** @teammateC  
**Location:** `src/projects/service.sql` — milestone reopen workflow  
**Comment:** The reopen logic should validate transition correctness before you emit the event. Right now it looks like the status update is accepted based on a broad state check, but we need explicit guards for invalid transitions such as reopening a milestone that was never closed, or reopening without a valid actor context. Please add stricter state validation and unit tests for these edge cases so the event contract cannot be triggered by a malformed or unauthorized state transition. This will make the system far more predictable and easier to reason about during audits or incident investigations.  

---

## Final Notes

This PR represents the first step toward a durable event-driven audit trail and notification layer. The core feature is useful and addresses a real operational need, but the correctness of the design depends on disciplined handling of privacy, retries, and state validation. The work is intentionally scoped to a clear domain trigger, but the pattern should be reused carefully going forward so additional event types do not inherit weak assumptions.
