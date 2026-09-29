#!/usr/bin/env bash
# Runs an S0.0A lab script with staging credentials from ~/.fuxia-staging.env.
# Refuses to run if anything points at production. Never prints credentials.
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"
STAGING_REF="faltxpkaicwpnlqaxrdu"
ENV_FILE="$HOME/.fuxia-staging.env"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
for v in "${STAGING_DB_URL:-}" "${STAGING_API_URL:-}"; do
  case "$v" in *"$PROD_REF"*) echo "ABORT: production ref in staging env" >&2; exit 1;; esac
  case "$v" in *"$STAGING_REF"*) ;; *) echo "ABORT: not the approved staging project" >&2; exit 1;; esac
done
cd "$(dirname "$0")/../.."
exec node "scripts/s00a/$1" "${@:2}"
