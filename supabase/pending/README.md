# Pending migrations (NOT picked up by the Supabase CLI)

The CLI only reads `supabase/migrations/`. Files here are prepared and reviewed but **not approved for application**.

A unit moves into `supabase/migrations/` only after all of these:
1. explicit approval of that unit;
2. its tests pass on staging;
3. `supabase db push --dry-run` against the target shows **only** that unit.

This prevents an accidental `supabase db push --linked` from applying unapproved S0.0A units to production.

Rollback scripts live in `supabase/rollbacks/<same-name>.down.sql`. They are applied by hand, only after approval.
