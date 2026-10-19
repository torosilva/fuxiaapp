#!/usr/bin/env bash
# Fuxia 360 · PRODUCCIÓN · ePayco "Onpage" → "Standard" (Mario 2026-10-19: "si"). Lo corre Mario.
# Por qué: docs/fuxia360/growth/ANALISIS_WEB_2026-06_A_2026-10.md §9 — en Onpage la ventana de ePayco se abre sola y queda en
# blanco 5-7 s; 4 de 5 pedidos perdidos de Colombia nunca intentaron pagar. Standard lleva a ePayco en la misma ventana (~4 s).
# Cambia SOLO epayco_type_checkout ("false" → "true"). No toca llaves, modo prueba, estados ni otra pasarela.
# Respaldo en el servidor: ~/f360-backups/prod-epayco/<ts>.json (chmod 600; contiene llaves, nunca se imprime).
# Reversión: scripts/f360/prod_epayco_standard.sh --revertir
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/fuxiaballerinas.com/public_html'
FROM=false; TO=true
if [ "${1:-}" = "--revertir" ]; then FROM=true; TO=false; fi
"${SSH[@]}" "set -e; cd $WP
  test \"\$(wp option get home)\" = 'https://fuxiaballerinas.com' || { echo 'ABORT: el destino no es fuxiaballerinas.com' >&2; exit 1; }
  cur=\$(wp option pluck woocommerce_epayco_settings epayco_type_checkout)
  [ \"\$cur\" = '$FROM' ] || { echo \"ABORT: epayco_type_checkout es '\$cur', se esperaba '$FROM'\" >&2; exit 1; }
  mkdir -p ~/f360-backups/prod-epayco && chmod 700 ~/f360-backups/prod-epayco
  ts=\$(date +%Y%m%d-%H%M%S); umask 077; wp option get woocommerce_epayco_settings --format=json > ~/f360-backups/prod-epayco/\$ts.json
  wp option patch update woocommerce_epayco_settings epayco_type_checkout '$TO' >/dev/null
  now=\$(wp option pluck woocommerce_epayco_settings epayco_type_checkout)
  [ \"\$now\" = '$TO' ] || { echo 'ABORT: no quedó el cambio' >&2; exit 1; }
  wp sg purge >/dev/null 2>&1 || true
  echo \"LISTO: ePayco = \$( [ '$TO' = true ] && echo Standard || echo Onpage ) · activo=\$(wp option pluck woocommerce_epayco_settings enabled) · prueba=\$(wp option pluck woocommerce_epayco_settings epayco_testmode) · respaldo ~/f360-backups/prod-epayco/\$ts.json\""
