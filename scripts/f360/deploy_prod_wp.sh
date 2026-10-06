#!/usr/bin/env bash
# Fuxia 360 · the ONLY way this repo writes to the PRODUCTION WordPress (fuxiaballerinas.com), approved by Mario as a permission rule.
# Installs the committed must-use plugins of tools/storefront/mu-plugins/produccion/ into wp-content/mu-plugins/ of production:
#   · every file must be tracked by git with no uncommitted changes;
#   · the previous version (if any) is backed up to ~/f360-backups/prod-mu/<timestamp>/ on the server;
#   · PHP syntax is checked ON THE SERVER before the file goes live (a broken file is never activated);
#   · then the SiteGround cache is purged. Nothing else on the site is touched.
# Rollback: copy the backup back (or delete the file) — printed at the end.
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/fuxiaballerinas.com/public_html'
SRC='tools/storefront/mu-plugins/produccion'
cd "$(dirname "$0")/../.."
files=$(git ls-files "$SRC/*.php")
[ -n "$files" ] || { echo "ABORT: no hay plugins en $SRC" >&2; exit 1; }
git diff --quiet HEAD -- "$SRC" || { echo "ABORT: $SRC tiene cambios sin commitear." >&2; exit 1; }
TS=$(date +%Y%m%d-%H%M%S)
"${SSH[@]}" "test \"\$(cd $WP && wp option get home)\" = 'https://fuxiaballerinas.com'" || { echo "ABORT: el destino no es fuxiaballerinas.com" >&2; exit 1; }
for f in $files; do
  name=$(basename "$f")
  "${SSH[@]}" "mkdir -p ~/f360-backups/prod-mu/$TS $WP/wp-content/mu-plugins && cat > ~/f360-backups/prod-mu/$TS/$name.new" < "$f"
  "${SSH[@]}" "php -l ~/f360-backups/prod-mu/$TS/$name.new >/dev/null" || { echo "ABORT: $name no pasa php -l; no se instaló." >&2; exit 2; }
  "${SSH[@]}" "if [ -f $WP/wp-content/mu-plugins/$name ]; then cp $WP/wp-content/mu-plugins/$name ~/f360-backups/prod-mu/$TS/$name.prev; fi; cp ~/f360-backups/prod-mu/$TS/$name.new $WP/wp-content/mu-plugins/$name"
  echo "instalado: $name ($(git log -1 --format=%h -- "$f"))"
done
"${SSH[@]}" "cd $WP && wp sg purge >/dev/null 2>&1 || true"
code=$(curl -sL -o /dev/null -w '%{http_code}' "https://fuxiaballerinas.com/?nc=$TS")   # / redirects to /mx/ by country
echo "Página de inicio después de instalar: http $code"
[ "$code" = "200" ] || { echo "ATENCIÓN: la tienda no respondió 200. Rollback: borrar o restaurar desde ~/f360-backups/prod-mu/$TS/" >&2; exit 3; }
echo "LISTO. Respaldo y rollback: ~/f360-backups/prod-mu/$TS/"
