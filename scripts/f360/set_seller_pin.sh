#!/usr/bin/env bash
# Fuxia 360 · set a seller's PIN in PRODUCTION (tgzg…) without the PIN ever touching git or a file.
# Run by Mario himself; it calls the owner RPC f360_set_seller_pin acting as Mario (owner), so the PIN rules, the hashing
# and the audit (seller_auth_events, "Mario Silva") are the database's own. The person must already have a seller role.
# Usage: scripts/f360/set_seller_pin.sh <phone digits, e.g. 525513667060> <4-digit PIN>
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"; MARIO="d11a8d33-cae6-46a5-9d0f-bd2516e8712b"
PHONE="${1:-}"; PIN="${2:-}"
[[ "$PHONE" =~ ^[0-9]{10,13}$ ]] && [[ "$PIN" =~ ^[0-9]{4}$ ]] || { echo "uso: $0 <teléfono solo dígitos> <PIN de 4 dígitos>" >&2; exit 2; }
T="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$T" in go-keyring-base64:*) T="$(printf '%s' "${T#go-keyring-base64:}" | base64 -d)";; esac
[ -n "$T" ] || { echo "ABORT: no hay sesión de la CLI de Supabase (supabase login)." >&2; exit 4; }
SQL="BEGIN;
DO \$\$ DECLARE uid uuid; BEGIN
  SELECT auth_user_id INTO uid FROM public.customers
    WHERE regexp_replace(phone, '\\D', '', 'g') IN ('$PHONE', regexp_replace('$PHONE', '^52', '521')) AND auth_user_id IS NOT NULL
    ORDER BY created_at LIMIT 1;
  IF uid IS NULL THEN RAISE EXCEPTION 'Ese teléfono no tiene cuenta en la app.'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '$MARIO', 'role', 'authenticated')::text, true);
  PERFORM public.f360_set_seller_pin(uid, '$PIN');
END \$\$;
COMMIT;"
out="$(python3 -c "import json,sys;print(json.dumps({'query': sys.stdin.read()}))" <<<"$SQL" \
  | curl -s -X POST "https://api.supabase.com/v1/projects/$PROD_REF/database/query" -H "Authorization: Bearer $T" \
      -H "Content-Type: application/json" --data-binary @- -w '\n%{http_code}')"
code="${out##*$'\n'}"
echo "$(date -u +%FT%TZ) SET-PIN phone=…${PHONE: -4} http=$code" >> "$HOME/fuxia360-respaldos/prod-sql.log"
if [ "$code" = "201" ]; then echo "PIN asignado (teléfono …${PHONE: -4})."; else echo "FALLÓ (http $code): ${out%$'\n'*}" | head -c 600 >&2; exit 5; fi
