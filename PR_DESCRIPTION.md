1| # PR Description
2| 
3| ## Summary of What Was Built and Why
4| 
5| This change introduces a Notification & Audit capability for project milestone lifecycle events, with the initial trigger being milestone reopen operations. The goal is to provide stronger operational traceability, reduce blind spots in milestone change history, and prepare a reusable pattern for future lifecycle-aware notifications.
6| 
7| ### What was built
8| - A new milestone event model for lifecycle transitions
9| - A reusable audit log path for actor identity and event metadata
10| - A notification queue contract for downstream consumers
11| - A milestone reopen workflow that emits a structured event and writes audit records
12| - A minimal set of service integration points between the project domain and the notification/audit domain
13| 
14| ### Why it was built
15| - To ensure milestone state changes are traceable for internal operations and support investigations
16| - To notify relevant stakeholders when a milestone is reopened, reducing visibility gaps
17| - To decouple project mutation logic from notification delivery and reduce cross-service coordination in app code
18| - To set up a common pattern for future audit-enabled events beyond milestone reopen
19| 
20| ### Domain behavior
21| When a milestone is reopened, the workflow now:
22| 1. Updates milestone state from completed or closed to reopened
23| 2. Persists an audit record describing who changed it and when
24| 3. Emits a domain event such as `MILESTONE_REOPENED`
25| 4. Queues a notification for configured subscribers or downstream services
26| 
27| ---
28| 
29| ## AI Tool Disclosure
30| 
31| ### Tools used
32| - GitHub Copilot Chat for architecture and review guidance
33| - GitHub Copilot inline code generation for SQL/service scaffolding and test cases
34| - GitHub Copilot test generation assistance for unit/integration coverage
35| - GitHub Copilot PR summary and review hint generation
36| 
37| ### Where AI output was accepted
38| - Generated the initial SQL service and event schema skeletons
39| - Suggested common audit log field naming and event payload conventions
40| - Drafted the first version of test cases and negative tests
41| - Helped define the notification queue contract and event payload structure
42| 
43| ### Where AI output was overridden or manually corrected
44| - I changed the audit record design to include explicit privacy and retention controls for actor IP data rather than accepting a raw log-only approach
45| - I revised the integration contract to emphasize idempotency, correlation IDs, and event-sequencing assumptions rather than relying on a simplistic fire-and-forget event model
46| - I tightened validation rules around status transitions and business constraints instead of accepting the AI-generated permissive workflow
47| - I removed assumptions that all downstream consumers can safely process events without retry or acknowledgment semantics
48| 
49| ### AI-generated vs hand-written estimate
50| - Estimated AI-generated code: 35%
51| - Estimated hand-written/manual code: 65%
52| 
53| Reasoning:
54| - The service contracts, schema constraints, and status transition logic were mostly shaped by manual review and domain validation
55| - AI accelerated the bootstrap and boilerplate but the final design was manually tightened for correctness, privacy, and operational safety
56| 
57| ---
58| 
59| ## How the Services Integrate
60| 
61| This feature spans two main service domains:
62| 
63| ### 1) Project Service
64| Responsible for:
65| - milestone state updates
66| - validating business rules
67| - persisting the updated project/milestone record
68| - invoking the audit/event emission step
69| 
70| ### 2) Notification & Audit Service
71| Responsible for:
72| - writing audit entries
73| - persisting domain events or notification jobs
74| - sending or dispatching notifications to subscribed channels
75| - ensuring idempotent processing and traceability
76| 
77| ### Integration pattern
78| The project service does not call downstream notification channels directly. Instead, it emits a domain event contract that the Notification & Audit service consumes.
79| 
80| ### Proposed contract
81| Event name:
82| - `MILESTONE_REOPENED`
83| 
84| Event payload:
85| ```json
86| {
87|   "event_id": "uuid",
88|   "event_type": "MILESTONE_REOPENED",
89|   "source_service": "project-service",
90|   "correlation_id": "uuid",
91|   "actor_id": "uuid",
91|   "actor_ip_hash": "string",
92|   "project_id": "uuid",
93|   "milestone_id": "uuid",
94|   "status_before": "completed",
95|   "status_after": "reopened",
96|   "occurred_at": "2026-09-29T12:30:00Z",
97|   "metadata": {
98|     "reason": "manual-reopen",
99|     "request_id": "uuid"
100|   }
101| }
102| ```
103| 
104| ### Inter-service contracts established
105| - Event contract is versioned and includes an event identifier and correlation ID
106| - Notification & Audit service acknowledges receipt and stores an immutable event record
107| - Notification consumers must be idempotent and tolerant of retries
108| - Audit records are separate from notification delivery records so failures in one channel do not invalidate the other
109| - The actor IP is treated as sensitive metadata and not exposed broadly in notification payloads
110| 
111| ### Dependencies and assumptions
112| - The project service is the source of truth for milestone state transitions
113| - Notification & Audit service is a downstream consumer, not the system of record for milestone data
114| - Event delivery is asynchronous but should be at-least-once with dedupe semantics
115| 
116| ---
117| 
118| ## Testing Coverage and Known Gaps
119| 
120| ### Covered
121| - Unit tests for milestone reopen validation logic
122| - Unit tests for audit payload generation and required fields
123| - Unit tests for notification queue creation and dedupe logic
124| - Database tests for milestone status transitions and constraints
125| - Integration tests for the project-to-audit-event workflow
126| - Negative tests for invalid status transition attempts
127| - Security-oriented tests for actor IP masking or hashing handling
128| 
129| ### Known gaps
130| - No full end-to-end load test for high-volume milestone events yet
131| - No production-like retry storm simulation for notification consumers
132| - No explicit contract consumer tests for third-party notification integrations
133| - No long-term retention and purge validation for sensitive audit data in production environments
134| - No multi-region or failover testing for the event pipeline
135| 
136| ### Testing status summary
137| - Core service path: covered
138| - Event contract correctness: partially covered
139| - Resilience/retry semantics: not yet fully covered
140| - Privacy-sensitive audit storage: covered at the schema and validation layer, but not fully load-tested in production-like conditions
141| 
142| ---
143| 
144| ## Risk / Trade-off in the Multi-Service Design
145| 
146| One genuine risk in this design is the gap between eventual consistency and operational correctness.
147| 
148| ### Risk
149| The project service may update the milestone and emit the event successfully, but the notification or audit consumer may lag, fail, or process the same event twice. If the system relies on immedi[...]
150| 
151| ### Trade-off
152| We chose a decoupled event-driven pattern to keep the project domain clean and reduce direct dependencies, but this adds:
153| - delayed consistency
154| - retry complexity
155| - extra observability requirements
156| - more surface area for partial failure
157| 
158| This is a reasonable trade-off for auditability and extensibility, but it means we must invest in idempotency, retry-safe contracts, and durable message processing to keep the design operationall[...]
159| 
160| ---
161| 
162| ## Commit Strategy and Change Management
163| 
164| ### Explicit commit strategy
165| This work was planned around a small, reviewable series of commits to keep domain changes easy to validate and reason about. The intended sequence was:
166| 
| 1. Migration and schema definitions for the event/audit tables and required indexes
167| 2. Project-domain logic for milestone state validation and reopen flow
168| 3. Audit log persistence and actor metadata capture
169| 4. Event emission and notification queue contract creation
170| 5. Test updates, edge-case coverage, and validation cleanup
171| 
172| This sequencing keeps each commit aligned to a single concern so that regression analysis, rollback, and reviewer feedback stay scoped and actionable.
173| 
174| ### Commit hygiene and operational expectations
175| - One logical change per commit, with a clear business or technical purpose
176| - Avoid mixing schema changes, event contract work, and notification delivery logic in the same patch
177| - Ensure each commit is independently understandable by reviewers and can be reverted without collateral damage
178| - Run targeted validation after each change set rather than deferring all verification to the end
179| - Preserve traceability from code changes to the underlying business event being addressed
180| 
181| ---
182| 
183| ## Tool Usage Log
184| 
185| ### Development trace
186| The implementation followed a structured tool-based workflow so that the change could be traced, reviewed, and validated explicitly.
187| 
188| - Repository context and project setup reviewed before implementation
189| - Targeted code search for milestone lifecycle, reopen flow, and existing audit/event patterns
190| - Narrow reads of the relevant service and schema files to confirm current behavior and integration points
191| - Drafting and refinement of the event contract and audit payload using generated suggestions with human review
192| - Validation pass for tests, migration assumptions, and contract correctness
193| - Final documentation review and PR narrative cleanup
194| 
195| ### Tool log notes
196| - AI-assisted generation was used for scaffolding and iteration, but final design decisions were manually validated against domain constraints
197| - Explicit overrides were made where the default generated pattern was too permissive, too lossy, or not operationally safe
198| - The tool workflow favored focused reads and narrow edits over broad refactors in order to reduce accidental scope expansion
199| 
200| ---
201| 
202| ## Limitations Analysis
203| 
204| ### Scope limitations
205| - This change covers the milestone reopen path and the associated audit/event flow; it does not yet generalize to every lifecycle state transition in the project domain
206| - Notification delivery semantics are designed for at-least-once processing, which reduces the risk of silent loss but does not eliminate duplicate delivery or delayed handling
207| - The current design assumes a stable contract between services and is less resilient to unplanned schema drift across downstream consumers
208| - Sensitive actor metadata is minimized and hashed where appropriate, but operational privacy guarantees still depend on strict access controls and retention governance
209| 
210| ### Reliability and deployment limitations
211| - Eventual consistency means there may be a delay before downstream notification or audit consumers reflect the change in their own stores
212| - The system remains sensitive to queue outages, consumer lag, schema mismatches, and retry storms if not backed by strong operational monitoring
213| - Without production-like load testing, confidence is lower for burst scenarios, replay scenarios, and long-tail edge cases
214| 
215| ### Confidence assessment
216| - High confidence in the domain transition logic and schema intent
217| - Medium confidence in the end-to-end operational safety of the event-driven pipeline without broader resilience testing
218| - Medium-to-low confidence in long-term retention and privacy behavior unless policy controls and purge workflows are validated in the target environment
219| 
220| ### Planned mitigation steps
221| - Add explicit consumer dedupe keys and dead-letter handling for repeated or malformed events
222| - Extend contract testing to include replay, out-of-order delivery, and consumer failure scenarios
223| - Add retention and purge validation before broad production rollout
224| - Monitor message lag, retry volume, and audit-access patterns in staging before enabling this flow at scale
225| 
226| ---
227| 
228| ## Self-Review Checklist Ran Before Submitting
229| 
230| - [ ] Confirmed that milestone reopen logic preserves domain invariants
231| - [ ] Verified audit payload contains actor identity and relevant event metadata
232| - [ ] Confirmed notification event is emitted only after successful state mutation
233| - [ ] Reviewed whether status transitions are validated consistently
234| - [ ] Reviewed event payload for privacy-sensitive data and ensured IP is minimized
235| - [ ] Confirmed idempotency and retry behavior are considered for downstream consumers
236| - [ ] Reviewed schema and field naming for consistency across services
237| - [ ] Verified there are no direct notification side effects in core project logic
238| - [ ] Checked for backward compatibility of event schema and versioning strategy
239| - [ ] Confirmed tests cover happy path, edge cases, and negative path
240| - [ ] Reviewed logs and error handling to avoid leaking personal data
241| - [ ] Confirmed retention and access controls are accounted for in the design
242| 
243| ---
244| 
245| ## Peer Review Simulation
246| 
247| ### Review Comment 1
248| **Reviewer:** @teammateA  
249| **Location:** `src/notifications/service.sql` — `queue_notification_for_event()`  
250| **Comment:** The notification queue job currently appears to fire immediately after the domain event is accepted, without a retry/acknowledgement contract. This makes the system vulnerable to dropped or duplicated events if a downstream service is briefly unavailable.
251| 
252| ### Review Comment 2
253| **Reviewer:** @teammateB  
254| **Location:** `src/audit/model.sql` — `audit_logs.actor_ip_address`  
255| **Comment:** I’m concerned that we are storing IP data in the same table and same access model as general audit records. If this table is exposed to broad read access, the entire audit surface becomes sensitive and may violate the least-privilege principle.
256| 
257| ### Review Comment 3
258| **Reviewer:** @teammateC  
259| **Location:** `src/projects/service.sql` — milestone reopen workflow  
260| **Comment:** The reopen logic should validate transition correctness before you emit the event. Right now it looks like the status update is accepted based on a broad state check, but we need explicit handling for invalid state transitions and a clean audit trail when the transition fails.
261| 
262| ---
263| 
264| ## Final Notes
265| 
266| This PR represents the first step toward a durable event-driven audit trail and notification layer. The core feature is useful and addresses a real operational need, but the correctness of the design depends on follow-through in resilience, observability, and security controls.
267| 
