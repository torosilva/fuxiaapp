# Fuxia 360 — Engineering Contract for Claude Code

## Mission
Evolve the existing Fuxia application into **Fuxia 360**, the omnichannel operating system for Fuxia Ballerinas.

The existing application is the foundation. Do **not** rebuild it from scratch.

## Non-negotiable working rules
1. **Do not code before auditing the current repository and the applicable specification.**
2. Treat existing production behavior as valuable. Prefer compatible migrations over destructive rewrites.
3. Never work directly on `main`. Use a feature/sprint branch.
4. Before changing a database object, inspect all migrations and every application reference to it.
5. `database/schema.sql` is **not assumed canonical**. Reconcile migrations + actual code usage.
6. Do not trust client-provided values for privileged operations such as price, totals, loyalty points, staff identity, inventory availability, or authorization.
7. Sensitive writes must be validated server-side and protected by appropriate RLS / server authorization.
8. Inventory-changing operations must be auditable and, where multiple writes form one business event, atomic.
9. WooCommerce must not be replaced. It remains the ecommerce engine.
10. Fuxia 360 becomes the canonical operational layer for product identity, physical inventory, locations, movements, reservations, customer intelligence, launches and growth intelligence as specified.
11. Do not create duplicate sources of truth.
12. Every implementation unit must include:
   - affected files
   - database/API impact
   - security considerations
   - migration/rollback considerations
   - tests or verification steps
   - acceptance criteria
13. Do not silently change loyalty, pricing, inventory, launch or attribution business rules.
14. Flag contradictions between documentation and repository reality before implementing.
15. Prefer simple operator UX. If Carolina or a store seller needs technical training for a routine operation, reconsider the design.

## Required reading order
1. `docs/fuxia360/00_MASTER_SPEC.md`
2. `docs/fuxia360/01_CURRENT_ARCHITECTURE.md`
3. `docs/fuxia360/02_TARGET_ARCHITECTURE.md`
4. `docs/fuxia360/03_DATA_MODEL.md`
5. `docs/fuxia360/04_SECURITY_MODEL.md`
6. `docs/fuxia360/05_GOVERNANCE.md`
7. `docs/fuxia360/06_WOOCOMMERCE_SYNC.md`
8. `docs/fuxia360/07_ADMIN_WEB.md`
9. `docs/fuxia360/08_OMNICHANNEL.md`
10. `docs/fuxia360/09_MIGRATION_PLAN.md`
11. `docs/fuxia360/10_SPRINTS.md`

## First assignment — audit only
**Do not modify application code or database migrations.**

Audit:
- all SQL migrations and schema files
- Supabase Edge Functions
- RLS policies
- WooCommerce integrations/webhooks
- inventory flows
- offline sales
- channels and staff
- authentication/authorization
- loyalty logic
- admin functionality
- current documentation

Create:

`docs/fuxia360/audit/CURRENT_STATE.md`  
`docs/fuxia360/audit/SCHEMA_AUDIT.md`  
`docs/fuxia360/audit/SECURITY_AUDIT.md`  
`docs/fuxia360/audit/INTEGRATION_AUDIT.md`  
`docs/fuxia360/audit/GAP_ANALYSIS.md`  
`docs/fuxia360/audit/SPRINT_0_IMPLEMENTATION_PLAN.md`

For every material finding, cite the repository file(s) and relevant code/SQL section. Do not begin Sprint 0 implementation until the audit is reviewed and explicitly approved.
