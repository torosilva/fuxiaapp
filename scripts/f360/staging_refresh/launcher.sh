#!/bin/bash
# Fuxia 360 · arranque de la copia nocturna (lo lanza launchd; ver docs/fuxia360/ops/STAGING_REFRESH.md).
# macOS no deja que launchd lea ~/Documents ("Operation not permitted"), así que la copia corre desde un clon propio
# fuera de Documentos, puesto cada noche en origin/fuxia-360: corre siempre el código publicado, nunca cambios locales.
# Se instala con: install -m 700 scripts/f360/staging_refresh/launcher.sh ~/.fuxia360/staging-nightly.sh
set -uo pipefail
export PATH="/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
CL="$HOME/.fuxia360/staging-refresh-repo"
notify() { osascript -e "display notification \"$1\" with title \"Fuxia staging\" subtitle \"Copia nocturna FALLÓ\"" >/dev/null 2>&1 || true; }
echo "── $(date '+%F %T') · copia nocturna"
if [ ! -d "$CL/.git" ]; then
  git clone -q --branch fuxia-360 https://github.com/torosilva/fuxiaapp.git "$CL" || { notify "no pude clonar el repositorio"; exit 1; }
fi
git -C "$CL" fetch -q origin fuxia-360 && git -C "$CL" checkout -q --detach --force origin/fuxia-360 \
  || { notify "no pude actualizar el clon"; exit 1; }
echo "código: $(git -C "$CL" log --oneline -1)"
exec /bin/bash "$CL/scripts/f360/staging_refresh/nightly.sh"
