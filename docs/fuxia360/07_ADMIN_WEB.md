# Fuxia 360 Admin Web

## 1. Purpose
Create an operator interface that is simpler than a traditional ERP and optimized for Fuxia's actual workflows.

Primary users:
- Carolina
- Mario
- authorized NovaMktLab team members
- future authorized operations staff

## 2. UX principle
Routine tasks should use business language, not database/ERP language.

Bad:
“Create inventory location allocation.”

Good:
“Llegaron productos” / “Mover inventario” / “Ajustar stock” / “Preparar lanzamiento”.

## 3. MVP navigation
### Today
- sales snapshot
- online/offline order counts
- inventory alerts
- pending approvals
- reservations
- launches blocked
- sync/incidents requiring attention

### Products
- product search
- variants by size/color
- price/cost according to permission
- stock by location
- Woo sync status
- Tier A/B/C
- launch/readiness
- product performance later

### Receive Merchandise
Critical Carolina workflow:
1. choose existing product or create new
2. choose/create color
3. enter quantity matrix by size
4. confirm cost/price if authorized
5. choose receiving location
6. attach/confirm product assets if available
7. assign initial tier
8. review total pairs
9. confirm receipt
10. system creates movements and queues/synchronizes Woo according to policy

Target: a normal receipt should be understandable without technical training.

### Inventory
- stock by location
- transfers
- adjustments
- low stock
- reconciliation/counts
- movement history

### Launch Center
- Product Ready
- Creative Ready
- Ecommerce Ready
- Demand Ready
- CRM/Data Ready
- blockers/owners/dates

### Customers
Later phase:
- Customer 360
- purchase history
- loyalty
- lifecycle
- preferences/size
- consent
- CRM activity

### Growth
Later phase:
- funnel
- CAC/MER
- experiments
- campaign performance
- contribution economics

## 4. Permissions
The web UI must not rely only on hidden menu items. Backend authorization/RLS must enforce permissions.

Examples:
- NovaMktLab may need launch/web/growth access but not unrestricted customer PII or product cost.
- Seller access should remain narrow.
- Carolina/admin may have broader operational rights.
- Mario needs architecture/data/growth administration appropriate to the agreed role.

## 5. Technical approach
Audit first. Recommend framework/repository layout after evaluating the current repo. Do not perform a monorepo migration solely because this document mentions an Admin Web.
