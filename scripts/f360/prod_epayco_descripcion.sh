#!/usr/bin/env bash
# Fuxia 360 · PRODUCCIÓN · texto de ePayco en el checkout (Mario 2026-10-19: "dale a la 1 mientras"). Lo corre Mario.
# Por qué: ePayco muestra el nombre de la titular legal de la cuenta, no "Fuxia Ballerinas", y ePayco no lo deja cambiar
# (ANALISIS_WEB_2026-06_A_2026-10.md §9). Se avisa antes para que la clienta no desconfíe.
# Cambia SOLO "description" de woocommerce_epayco_settings (el texto bajo el método de pago). Respaldo en el servidor.
# Uso: scripts/f360/prod_epayco_descripcion.sh [--staging4] [--revertir]
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
HOST=fuxiaballerinas.com; BK=prod-epayco
OLD='Checkout ePayco (Tarjetas de crédito,débito,efectivo)'
NEW='Paga con tarjeta de crédito, débito o efectivo. Te llevaremos a ePayco, la pasarela de pago segura de Fuxia Ballerinas en Colombia; ahí verás el nombre de la titular de nuestra cuenta.'
for a in "$@"; do
  case "$a" in
    --staging4) HOST=staging4.fuxiaballerinas.com; BK=staging4-epayco ;;
    --revertir) t="$OLD"; OLD="$NEW"; NEW="$t" ;;
    *) echo "uso: $0 [--staging4] [--revertir]" >&2; exit 2 ;;
  esac
done
"${SSH[@]}" "set -e; cd ~/www/$HOST/public_html
  test \"\$(wp option get home)\" = 'https://$HOST' || { echo 'ABORT: el destino no es $HOST' >&2; exit 1; }
  cur=\$(wp option pluck woocommerce_epayco_settings description)
  [ \"\$cur\" = '$OLD' ] || { echo 'ABORT: el texto actual no es el esperado; no se cambió nada' >&2; exit 1; }
  mkdir -p ~/f360-backups/$BK && chmod 700 ~/f360-backups/$BK
  ts=\$(date +%Y%m%d-%H%M%S); umask 077; wp option get woocommerce_epayco_settings --format=json > ~/f360-backups/$BK/\$ts.json
  wp option patch update woocommerce_epayco_settings description '$NEW' >/dev/null
  [ \"\$(wp option pluck woocommerce_epayco_settings description)\" = '$NEW' ] || { echo 'ABORT: no quedó el cambio' >&2; exit 1; }
  wp sg purge >/dev/null 2>&1 || true
  echo \"LISTO ($HOST): \$(wp option pluck woocommerce_epayco_settings description) · respaldo ~/f360-backups/$BK/\$ts.json\""
