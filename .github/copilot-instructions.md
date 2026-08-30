# Copilot / Repository Instructions

This document describes the technology stack, architecture conventions for a multi-service layout, coding standards, security rules relevant to a multi-tenant B2B SaaS product (authentication, authorization, data exposure), and testing expectations. Use it as the canonical reference for contributor behavior, CI expectations, and secure design choices.

---

## 1) Technology stack (recommended / canonical)
- Language(s):
  - SQL: PostgreSQL (primary relational DB)
- API:
  - HTTP/REST (JSON) for external public APIs
  - gRPC for high-performance internal service-to-service calls (optional)
- Auth / Identity:
  - OAuth2 / OpenID Connect (OIDC) provider for SSO (Auth0, Okta, keycloak, or cloud IAM)
- Infrastructure:
  - Containers: Docker; orchestrate with Kubernetes (or managed K8s)
  - IaC: Terraform
  - Secrets: Azure Key Vault
- Observability:
  - Logging: structured JSON logs to centralized log store
  - Metrics: Prometheus + Grafana
  - Tracing: OpenTelemetry / Jaeger
- CI/CD:
  - GitHub Actions and GitHub Environments
- DB Migrations:
  - Use a migrations tool: sql-migrate

---

## 2) Architecture conventions — multi-service layout
- Repo layout and service boundaries
  - Prefer one service per repository for independently deployable services. If monorepo, keep strict top-level directories per service (service-a/, service-b/).
  - Each service must include:
    - Dockerfile
    - CI workflow (in .github/workflows)
    - README with run/test instructions
    - migrations/ and seeds/ directory
- Service responsibilities
  - Single responsibility principle: a service owns a specific business capability and its data.
  - Avoid direct DB access across services. Use API contracts or events for cross-service data access.
- Data ownership
  - Each service owns its schema and migration history.
  - Shared data should be exposed via well-defined APIs or event streams—no cross-service foreign keys.
- Contracts and API compatibility
  - Publish API contracts (OpenAPI / protobuf) in each service repo.
  - Version APIs (v1, v2) — do not perform breaking changes without major/version bump and migration path.
- Deployment
  - Keep environment parity between dev/staging/production.
  - Services must support graceful shutdown, health checks (readiness/liveness), and readiness gating before traffic.

---

## 3) Database & multi-tenancy conventions
- Tenant models (choose one and apply consistently)
  - Shared schema with tenant_id column (recommended for many B2B SaaS with many small tenants).
  - Isolated schemas or databases for high-security or heavy-compute tenants.
- If using shared schema:
  - All tenant-scoped tables MUST include a non-null `tenant_id` (UUID) column.
  - Use PostgreSQL Row Level Security (RLS) policies to enforce tenant isolation:
    - Create RLS policies that require `current_setting('app.current_tenant', true)::uuid` or `jwt_claim` context to match `tenant_id`.
    - Deny access by default; explicitly grant through policies.
  - Never rely solely on application-level filtering—enforce at DB level where possible.
- Migrations & multi-tenant data
  - Migrations run once per schema (or per DB for isolated tenants). Have safe migration practices for live tenants:
    - Backfill or background migration patterns
    - Add new columns nullable with defaults, backfill in batches, then set NOT NULL
- Indexing
  - Include `tenant_id` in compound indexes for tenant-scoped queries to avoid full-table scans.

---

## 4) Authentication (how users and services identify)
- Human users
  - Use OIDC/OAuth2 with SSO for enterprise tenants.
  - Support SCIM / Just-In-Time provisioning for enterprise user lifecycle where needed.
  - Preferred token type: short-lived JWT access tokens + refresh tokens; or opaque tokens validated at an auth server.
- Machine-to-machine / service auth
  - Use mTLS or signed tokens (short-lived) for service identity.
  - Prefer an internal auth service or service mesh with identity.

Best practices:
- Do not accept user-supplied JWTs as-is; validate issuer, audience, signature, expiry, and required claims.
- Always validate tokens server-side, and map claims to scoped principals/roles.

---

## 5) Authorization (roles, scopes, and RBAC)
- Use Role-Based Access Control (RBAC) combined with attribute-based checks:
  - Tenant-level roles: tenant-admin, tenant-user, billing-admin, etc.
  - Resource-level permissions: scope strings or resource ACLs for fine-grained control.
- Enforce authorization in two layers:
  1. API gateway / middleware: coarse checks (is tenant member, is role allowed)
  2. Service-level checks: fine-grained permission checks and ownership checks (e.g., project.owner_id == user_id)
- Principle of least privilege: tokens/certificates grant only the scopes required.
- Audit all authorization failures and sensitive policy changes.

---

## 6) Data exposure and privacy rules
- Minimize data returned by default:
  - Always follow the "only include fields that the caller is authorized to see" rule.
  - Use DTOs/serializers that explicitly list permitted fields per role.
- Sensitive data
  - PII must be encrypted at rest and redacted or masked in logs and APIs.
  - Examples: SSNs, payment details, personal emails (if required).
- Data residency & retention
  - Respect tenant/regional data residency requirements. If supporting multiple regions, maintain per-region data stores.
  - Establish data retention and deletion policies; implement safe deletion workflows (soft delete followed by irreversible deletion after retention window).
- Telemetry & logging
  - Never log raw PII or full personal data. Use hashing or redaction.
  - Keep logs searchable by tenant id and correlation id (avoid mixing tenant data in single search views).

---

## 7) Security rules & operational controls
- Transport & storage
  - Enforce TLS everywhere (ingress, service-to-service).
  - Encrypt data at rest (DB, backups, object storage).
- Secrets management
  - Do not check secrets into source control. Use a secrets manager.
  - Rotate secrets regularly and provide automated rotation where possible.
- Network & perimeter
  - Zero trust: minimize public exposure; use private networks for internal traffic.
  - Use WAF and rate limiting on public APIs.
- Dependency and supply-chain security
  - Run dependency scanning (Snyk/Dependabot/OSS scanners) in CI.
  - Pin production images and use vulnerability scanning for images.
- Static & dynamic analysis
  - Integrate SAST (static analysis) and DAST (dynamic scanning) in CI for each PR or nightly runs.
- Incident response & auditability
  - Centralized audit logs recording security events (login, token issuance, authz failures, privilege changes).
  - Retain logs for forensic timelines as required by policy.
- Secure defaults & hardening
  - Fail closed: default deny for endpoints and policies.
  - Use least-privilege IAM roles for cloud resources.
- Third-party integrations
  - Vet third-party vendors for security/compliance (SOC2/HIPAA where relevant).
  - Isolate third-party access with per-tenant service accounts when possible.

---

## 8) Tenant onboarding & lifecycle security
- Onboarding
  - Provision tenant record, assign tenant_id, create tenant admin, and enforce password/SSO setup.
- Offboarding
  - Ensure tenant data export and deletion processes; keep an audit trail.
  - Deactivate tenant credentials immediately upon deprovisioning.
- Billing & metering
  - Billing services must be separate and have limited access to tenant data (tokenize or restrict).

---

## 9) Coding standards & development workflow
- Style & formatting
  - Enforce formatting with linters and formatters (gofmt / eslint / black / prettier).
  - Use type-checking (TypeScript strict mode or static typing in Go).
- Testing & coverage
  - Unit tests for business logic; aim for >70% coverage in critical modules.
  - Integration tests that run against a local or ephemeral DB (use testcontainers).
- Commits & PRs
  - Use descriptive commit messages: short summary, blank line, and detailed description where needed.
  - Require PRs for all changes; enable branch protection: require at least one reviewer, passing CI, and no failing checks.
- Code review
  - Reviews must focus on correctness, security implications, and backwards compatibility.
- Secrets & configuration
  - Strictly use environment-based configuration that reads from secure stores in CI/Prod.
- Documentation
  - Keep README for each service up-to-date: local dev, expected env vars, how to run migrations, how to run tests.

---

## 10) Testing expectations (unit, integration, e2e, contract)
- Unit tests
  - Fast, deterministic, no external services. Mock dependencies and network calls.
- Integration tests
  - Run against a realistic DB (Postgres) and cache (Redis) instance; use ephemeral containers in CI.
  - Cover database migrations, basic CRUD flows, and RLS/policy enforcement for multi-tenancy.
- Contract tests
  - For service-to-service APIs, publish and verify OpenAPI/protobuf contracts.
  - Use contract testing (Pact or similar) for consumer/producer validation.
- End-to-end tests
  - Run on staging environment with representative data. Include key user journeys: signup, SSO login, create project, cross-tenant isolation checks.
- Security tests
  - Include tests for authentication/authorization failures, RLS bypass attempts, and common OWASP top 10 checks (in CI or DAST).
- Performance and load tests
  - Run periodic load tests for latencies and throughput and track regressions.
- Test data and fixtures
  - Use realistic but synthetic test data; never use production PII in tests.
- CI policy
  - All PRs must pass unit + lint + basic integration checks before merging to development; releases require full integration + e2e + security scans.

---

## 11) Deployment and release process
- Branching and release rules
  - Developer work in feature branches → development branch → main via PR.
  - Main branch is always deployable.
- Releases
  - Tag releases and publish changelogs. Use semantic versioning where appropriate.
- Database changes
  - Deploy schema-migrations before dependent code changes when possible (backwards-compatible migrations).
  - Ensure migration rollback plans and backups exist.
- Rollbacks
  - Implement safe rollback or blue/green deployments to minimize downtime.

---

## 12) Operational best practices
- Monitoring and SLOs
  - Define SLOs and error budget per service.
  - Alert on SLI violations, high error rates, and high latency.
- Supportability
  - Include debug endpoints gated behind RBAC (not exposed publicly).
  - Correlate logs with request/trace ids to speed up debugging.
- Backups and DR
  - Regular DB backups and tested restore procedures.
  - Periodic disaster recovery drills.

---

## 13) Quick checklist for reviewers (PR checklist)
- Code compiles, lints, and tests pass
- No secrets in diffs
- DB migrations included and safe
- RLS and tenant_id checks are covered (if touching data access)
- Authentication/authorization is validated for new endpoints
- API contract changes documented and versioned
- Security scans pass (or findings acknowledged with ticket)
- README / run instructions updated if behavior changed


Preferred next step? (e.g., "commit to development" or "create PR template")
