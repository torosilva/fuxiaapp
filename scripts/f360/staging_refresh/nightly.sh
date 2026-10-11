#!/usr/bin/env bash
# Fuxia 360 · copia nocturna producción → staging (la lanza launchd a las 3:30; ver docs/fuxia360/ops/STAGING_REFRESH.md).
# 1) Tienda real → staging4 (woo_refresh.sh). 2) Supabase prod → staging (refresh.sh). Si la tienda se copió bien, Supabase
# conecta staging4 con el catálogo de prod (--woo-mirrored: mismos IDs de producto); si falló, Supabase se copia igual sin eso.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if "$HERE/woo_refresh.sh" --apply; then
  exec "$HERE/refresh.sh" --apply --woo-mirrored
else
  exec "$HERE/refresh.sh" --apply
fi
