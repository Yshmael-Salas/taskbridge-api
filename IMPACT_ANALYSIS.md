# Impact Analysis for TaskBridge API

## Overview
This analysis covers the current TaskBridge API schema and service layer for the `projects` domain, implemented in:

- `src/projects/model.sql`
- `src/projects/service.sql`

The code introduces the base data model for teams and projects, along with business functions for creating, updating, retrieving, deleting, and moving projects between teams.

## Summary of Changes
The current implementation adds:

- A `teams` table with a unique `name` and automatic UUID generation
- A `project_status` enum with values: `planned`, `active`, `completed`, and `archived`
- A `projects` table with UUID primary keys, team linkage, status tracking, audit timestamps, and an updated-at trigger
- Several PostgreSQL functions to support common project operations

## Functional Impact

### 1. Data Model Expansion
The schema changes expand the domain model from a minimal project container to a proper team-based project management structure.

Impact:
- New team-level organization is enabled for projects
- Projects can now be categorized by team and lifecycle state
- Every project records creation and update timestamps for traceability

Business effect:
- The API can now support team-based project filtering and ownership workflows
- Reporting and dashboards can segment work by team and project status

### 2. Project Lifecycle Management
The `project_status` enum creates a clear lifecycle model for each project.

Supported statuses:
- `planned`
- `active`
- `completed`
- `archived`

Impact:
- Allows consistent status tracking across all project records
- Enables filtering, reporting, and workflow automation based on project stage
- Provides a standard vocabulary for downstream consumers of the API

### 3. CRUD Support for Projects
The service layer adds direct SQL functions for common operations:

- `create_project(...)`
- `update_project_status(...)`
- `get_projects_by_team(...)`
- `delete_project(...)`
- `move_project_to_team(...)`

Impact:
- Reduces application-layer logic for basic project operations
- Ensures core project actions are reusable across service code and database clients
- Improves consistency by centralizing business rules in database functions

## Technical Impact

### 1. Schema Constraints and Data Integrity
The schema introduces data integrity safeguards:

- `teams.name` is unique
- `projects.team_id` references `teams(id)` with `ON DELETE SET NULL`
- `projects.status` is not null and constrained to `project_status`
- `projects.updated_at` is automatically refreshed by a trigger

Impact:
- Prevents duplicate team names
- Ensures project status stays within a valid domain
- Keeps timestamps current when records are updated

### 2. Query Performance
Indexes are added for:

- `projects(team_id)`
- `projects(status)`

Impact:
- Team-based lookups and status filtering should perform efficiently
- This helps with common project dashboards, queues, and filters

### 3. Timestamp Management
The trigger `trg_projects_updated_at` updates `updated_at` before each row change.

Impact:
- Maintains accurate audit metadata
- Supports last-modified tracking in UI and integrations
- Helps with freshness checks in downstream systems

## Deployment and Migration Impact
This change has migration implications for any existing database:

- The `uuid-ossp` extension must exist
- The `project_status` enum is created only if missing
- The `teams` and `projects` tables are created only if they do not already exist
- Existing data may need to be backfilled into `teams` and mapped into `projects.team_id`

Risk considerations:
- Existing project records without team associations may be represented as `NULL`
- Downstream code must account for optional team IDs when loading projects
- Any application logic expecting only one team or one project status may need review

## Risks and Edge Cases

### 1. Nullable Team Assignment
`projects.team_id` is nullable because the foreign key uses `ON DELETE SET NULL`.

Risk:
- A project may temporarily exist without an assigned team
- Queries expecting all projects to belong to a team may need filtering or validation

### 2. Delete Semantics
`delete_project(...)` removes a project by ID and returns a boolean success flag.

Risk:
- The function does not currently enforce authorization or soft-delete behavior
- If the project does not exist, it returns `FALSE` but does not raise an error

### 3. Status Transition Logic
The schema allows any valid status change via `update_project_status(...)` but does not enforce business rules like:

- a project cannot move from `completed` back to `planned`
- `archived` projects may be restricted from further edits

Risk:
- Business workflows may require application-level validation beyond the database schema

### 4. Trigger Reliability
The trigger ensures `updated_at` changes during updates, but it does not explicitly handle `INSERT` behavior beyond default values.

Risk:
- If application code bypasses the table defaults, `updated_at` may need explicit assignment
- The current trigger only fires on update, not on insert

## Benefits
The current implementation adds meaningful value to the product:

- Team-based project organization
- Consistent lifecycle tracking
- Better data quality through validation and indexing
- Clean database-level access patterns for project operations
- Improved reporting and operational visibility

## Recommendation
This is a strong foundation for the TaskBridge project domain. To maximize reliability, the next step should be to add:

- application-level validation around status transitions
- explicit permission checks for project mutations
- integration tests for each SQL function
- migration scripts for real production upgrade paths

## Conclusion
The changes introduce a scalable and maintainable project model for TaskBridge. The schema and stored procedures provide a solid base for team-based project management, while also highlighting a few areas where business rules and validation should be enforced outside the database layer to preserve operational consistency.
