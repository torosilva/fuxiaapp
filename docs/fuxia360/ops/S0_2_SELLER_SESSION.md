# S0.2 — Authenticated seller session (final design, built on Track C · C1)

Status:
- **Staging:** implemented and tested (migrations `20261001000100`, `20261001000200`).
- **App:** changed behind a flag. The flag is off by default, and the app's `.env` points to **production**.
- **Production:** nothing.

## 1. Sources of authority

| Question | The server derives it from | NO LONGER an authority |
|---|---|---|
| Who is operating? | `auth.uid()` of the caller's own Supabase session (own phone login) | route params, `staff.id` sent by the app, phone, `user_metadata` |
| What may she do? | `f360.user_roles.role` (`seller` / `operator` / `owner`; `viewer` reads only) | `customers.role` (user-editable, P0-1) |
| Where may she operate? | `f360.location_assignments` (active; several allowed, D-L2) | `staff.channel_id`, a channel picked from a public list |
| Where is she operating now? | the **shift session** (`f360.seller_sessions.location_id`) | any `location_id` / `channel_id` in a request. A different one is refused and audited |
| Is it really her at the store? | a **PIN hash** (bcrypt, pgcrypto) checked for **that** person only | the plaintext `public.staff.pin` readable by anyone (P0-3) |

- **READ vs OPERATE** (approved):
  - A seller **reads** stock of every location (role level = viewer), so she can tell a customer "hay en otra tienda".
  - She **operates** only through `f360.require_seller_session(token, location_claim)`: a valid shift at an **assigned** location, re-checked live on every call.
- **Interim, until S0.3:** today's sale screen still writes `channel_inventory` / `offline_sales` through the legacy authenticated RLS, which checks `customers.role IN (staff, admin)`. So under A2 option (a), sellers keep `customers.role='staff'` until S0.3's `pos-sale` replaces that path; S0.3 then checks the shift session instead. This is the **only** place `customers.role` still matters, and it is scheduled to disappear.

## 2. Flow

1. The seller logs in with **her own account** (existing OTP). With no session there is no seller mode at all: the onboarding entry was removed, and `/vendedora` shows "inicia sesión".
2. "Modo Vendedora" appears in Perfil when the **f360 role** is seller/operator/owner (with the flag on; otherwise the legacy `customers.role` rule).
3. Locations come from `f360_my_locations()`: only her assignments. If there is one, it is chosen automatically.
4. PIN → `f360_start_seller_shift(location, pin)`:
   - order of checks: role → assignment (checked **before** the PIN, so no attempt is consumed) → PIN exists → lock → bcrypt compare;
   - on success: any previous shift is closed, and a 32-byte random token is returned. **Only its sha256 is stored.**
5. Every operation: `require_seller_session` checks the session belongs to the caller, is not revoked/expired/idle, the role still allows it, the **assignment is still active**, and the location is still active and sellable. Then it touches `last_seen_at`.
6. "Salir" → `f360_end_seller_shift`. The token lives **only in memory** in the app; closing the app means a new PIN.

## 3. Parameters — RECOMMENDED, pending approval

The values live in one place, `f360.seller_params()`, so changing them is a one-line migration.

| Parameter | Recommended | Why |
|---|---|---|
| PIN length | **4 digits** | Already decided (Q2) |
| Consecutive wrong PINs before a temporary lock | **5** | Typos happen at a busy counter. 5 tries of 4 digits = 0.05% chance of guessing, and the attacker must already hold the seller's **own** logged-in phone |
| Temporary lock | **15 min** | Long enough to stop guessing, short enough not to stop a sale for long. A manager can unlock earlier |
| Hard lock | **10 wrong PINs in 24 h** → locked until an owner/operator unlocks | Stops slow guessing across several temporary locks |
| Absolute shift length | **12 h** | Covers a full store day or a bazaar day without a second PIN. It ends by the next day |
| Inactivity expiry | **120 min** | A seller who leaves the phone must re-enter the PIN; normal pauses between sales don't force it. **Alternative:** 60 min if Mario prefers stricter |
| Changing location | **Closes the current shift**; a new PIN is required at the new location | One active shift per person. Every sale is unambiguous about where it happened |
| Revoking a role or an assignment during a shift | **Immediate**: triggers revoke the sessions, **and** every operation re-checks live state | Tested: the next call fails with "Tu turno terminó (asignación retirada)" |
| PIN reset | Revokes all active shifts of that person | Old PIN and old token stop working at once |
| Who sets/resets PINs | Owner. Unlock: owner or operator | The PIN is never shown again after it is set (Q2) |

## 4. Audit (`f360.seller_auth_events`, append-only)

- **Events:** `shift_start`, `bad_pin`, `locked`, `hard_locked`, `blocked_locked`, `not_assigned`, `not_seller`, `no_pin`, `pin_set`, `unlock`, `shift_end`, `revoked`, `location_mismatch`, `expired`, `denied`.
- **Each row records:** person (id + name), location (id + name), detail and time.
- **Commit behavior:** denials **return** instead of raising, so the audit row is committed. This was found and fixed during implementation (migration `20261001000200`).
- **Read access:** owners/operators, via `f360_seller_audit()`.

## 5. Not done here (by design)

- The new sale (C3) and `pos-sale` (S0.3).
- Linking `public.staff.auth_user_id`. Not needed for the new flow; the legacy screens keep working.
- Hiding PINs in the legacy admin UI.
- Production rollout of the app flag.
