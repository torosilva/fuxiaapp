#!/usr/bin/env bash
# Fuxia 360 · turns PRODUCTION Bandeja e-mails on (Mario 2026-10-30): Vault 'f360_email_url' + 'f360_email_secret' (same value as the
# f360-email Edge env F360_EMAIL_SECRET, from ~/.fuxia-email.secret). With both present, f360.email_tick() (trigger + cron
# 'f360-email-retry') calls f360-email. Never prints the secret: it travels only inside the TLS request body.
# Prerequisite: scripts/f360/deploy_prod_function.sh f360-email. Rollback (e-mails off): delete both Vault entries
#   (SELECT vault... DELETE FROM vault.secrets WHERE name IN ('f360_email_url','f360_email_secret')) — the outbox keeps queuing.
set -euo pipefail
umask 077
REF="tgzgiwfzddsghnxgkcqd"; URL="https://$REF.supabase.co/functions/v1/f360-email"; FILE="$HOME/.fuxia-email.secret"
[ -s "$FILE" ] || { echo "ABORT: falta $FILE (despliega f360-email primero)"; exit 1; }
T="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$T" in go-keyring-base64:*) T="$(printf '%s' "${T#go-keyring-base64:}" | base64 -d)";; esac
[ -n "$T" ] || { echo "ABORT: sin sesión de la CLI de Supabase"; exit 4; }
# the function must accept this secret before the database starts calling it. NOTE: this call already SENDS what is pending
# (run supabase/pase/20261030_bandeja_seguimiento.sql first so old staging-prefixed notices are fixed or skipped).
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Authorization: Bearer $(tr -d '\n' < "$FILE")" -H 'Content-Type: application/json' -d '{"action":"send"}')
[ "$code" = "200" ] || { echo "ABORT: f360-email no acepta el secreto (http $code)"; exit 2; }
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
python3 - "$FILE" "$URL" > "$TMP" <<'PY'
import json, sys
v = open(sys.argv[1]).read().strip(); url = sys.argv[2]
assert len(v) == 64 and all(c in '0123456789abcdef' for c in v)
q = """DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'f360_email_url') THEN PERFORM vault.update_secret((SELECT id FROM vault.secrets WHERE name = 'f360_email_url'), '%s');
  ELSE PERFORM vault.create_secret('%s', 'f360_email_url'); END IF;
  IF EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'f360_email_secret') THEN PERFORM vault.update_secret((SELECT id FROM vault.secrets WHERE name = 'f360_email_secret'), '%s');
  ELSE PERFORM vault.create_secret('%s', 'f360_email_secret'); END IF;
END $$; SELECT count(*) AS n FROM vault.secrets WHERE name IN ('f360_email_url', 'f360_email_secret')""" % (url, url, v, v)
print(json.dumps({'query': q}))
PY
curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" -H "Authorization: Bearer $T" -H "Content-Type: application/json" --data-binary @"$TMP" \
  | python3 -c "import json,sys; r=json.load(sys.stdin); n=(r[0].get('n') if isinstance(r,list) and r else None); print('vault: entradas de correo =', n); sys.exit(0 if n==2 else 1)"
echo "LISTO: correos de la Bandeja encendidos en producción."
