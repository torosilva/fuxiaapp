#!/usr/bin/env bash
# P2.2 local acceptance: fresh throwaway Woo + staging demo reset + local target registration.
# STAGING + LOCAL ONLY (run.sh / lib.mjs refuse production). Never touches any external WooCommerce.
set -euo pipefail
cd "$(dirname "$0")/../.."
tools/woo-docker/reset.sh >/dev/null 2>&1
echo "local Woo recreated"
scripts/s00a/run.sh ../f360/demo_reset.mjs | tail -1
scripts/s00a/run.sh ../f360/woo_local_target.mjs
