#!/bin/bash
# Fuxia 360 · Growth P0-C: captura diaria de Clarity (lo lanza launchd a las 6:30). Mientras Growth P0 no esté en producción, el historial
# de Clarity vive en ~/fuxia360-respaldos/clarity/ y se reimporta a staging cada día (la copia nocturna de las 3:30 borra staging).
# Usa el mismo clon fuera de Documentos que la copia nocturna (macOS no deja a launchd leer ~/Documents): corre el código publicado.
# 3 de las 10 llamadas diarias de Clarity. Cuando se autorice el pase a producción, el cron f360-clarity de prod lo reemplaza: desinstalar esto.
# Instalar:    install -m 700 scripts/f360/clarity_capture_launcher.sh ~/.fuxia360/clarity-captura.sh
#              cp scripts/f360/com.fuxia360.clarity-captura.plist ~/Library/LaunchAgents/
#              launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.fuxia360.clarity-captura.plist
# Desinstalar: launchctl bootout gui/$(id -u)/com.fuxia360.clarity-captura && rm ~/Library/LaunchAgents/com.fuxia360.clarity-captura.plist
set -uo pipefail
export PATH="/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
CL="$HOME/.fuxia360/staging-refresh-repo"
notify() { osascript -e "display notification \"$1\" with title \"Fuxia Clarity\" subtitle \"Captura diaria FALLÓ\"" >/dev/null 2>&1 || true; }
echo "── $(date '+%F %T') · captura de Clarity"
if [ ! -d "$CL/.git" ]; then
  git clone -q --branch fuxia-360 https://github.com/torosilva/fuxiaapp.git "$CL" || { notify "no pude clonar el repositorio"; exit 1; }
fi
git -C "$CL" fetch -q origin fuxia-360 && git -C "$CL" checkout -q --detach --force origin/fuxia-360 || { notify "no pude actualizar el clon"; exit 1; }
cd "$CL" || exit 1
scripts/s00a/run.sh ../f360/staging_growth_p0_capture.mjs clarity || notify "Clarity no respondió (revisa el log)"
scripts/s00a/run.sh ../f360/staging_growth_p0_capture.mjs clarity-reimport > /dev/null || notify "no pude reimportar a staging"
