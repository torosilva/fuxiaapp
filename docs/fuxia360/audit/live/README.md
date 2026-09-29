# S0.1a live schema snapshot

| File | Content |
|---|---|
| `schema.sql` | Byte-identical output of `supabase db dump --linked` (schema-only, `public`), run by the project owner on 2026-09-24 against `tgzgiwfzddsghnxgkcqd`. |
| `storage_policies.sql` | Policies/RLS flags extracted from the `storage` schema-only dump (the remaining Supabase-managed internals are not committed). |

- **Schema only. No row data.** Reviewed before commit for secrets, credentials, emails, phone numbers and URLs: none found.
- **Read-only reference. Never execute against production.** It will become the input for the S0.1b migration baseline.
- Line numbers cited in `../LIVE_RECONCILIATION.md` refer to `schema.sql`.
