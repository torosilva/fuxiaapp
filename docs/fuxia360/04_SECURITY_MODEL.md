# Security Model

## 1. Principle
The mobile/web client is not a trusted authority for privileged business facts.

The server must independently validate authorization and business-critical values.

## 2. P0 items from reviewed repository
The audit must verify and remediate, subject to approval:

### Staff PIN
The reviewed schema stores `staff.pin` as text, and reviewed RLS documentation acknowledges that authenticated users can read operational tables. Target:
- PIN not exposed through ordinary client table reads
- PIN stored using an appropriate one-way password/PIN hashing approach
- validation server-side
- staff session/authorization model
- brute-force/rate-limit considerations
- audit trail for staff access

### Offline sale
The reviewed seller flow updates inventory from the client before/around sale creation. Target:
- one server-side command/RPC/function for the sale business event
- verify authenticated/authorized staff
- verify staff-location relationship
- fetch authoritative inventory records
- validate available quantity
- derive authoritative price/total server-side
- create sale + items + movement(s) + loyalty consequences atomically
- idempotency key / double-submit protection
- rollback on failure

### claim-sale
The audit must verify whether `scan_qr` can be called without a valid staff authorization context and whether client-supplied items/total can influence authoritative loyalty/sale values. Service-role use must never turn untrusted request fields into privileged writes without validation.

## 3. RLS target
RLS must reflect roles and ownership, not simply `authenticated`.

At minimum distinguish:
- customer
- staff
- admin
- privileged server/service operations

NovaMktLab web access must be least-privilege by function; agency access should not automatically expose all customer or financial data.

## 4. Secrets
Woo credentials, service-role keys and other privileged secrets remain server-side only.

## 5. Auditability
Sensitive events should record actor/context where appropriate:
- inventory adjustment
- receipt confirmation
- transfer
- approval/rejection
- price/cost changes
- reservation override
- staff/admin actions
- manual customer/loyalty adjustment

## 6. Privacy
Customer data access should be purpose-limited. Governance determines which roles can view PII, customer history, economics and campaign data.

## 7. Deployment rule
No P0 security migration goes directly to production without:
- migration review
- affected-flow test plan
- rollback path
- verification of customer, staff and admin critical journeys
