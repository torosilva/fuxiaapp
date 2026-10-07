#!/usr/bin/env bash
# Fuxia 360 · installs the committed STAGING4 mu-plugins of tools/storefront/mu-plugins/staging4/ (staging4 only).
# Same guards as production: committed files only, target must answer as staging4, server php -l before activating,
# backup of the previous file to ~/f360-backups/staging4-mu/<ts>/, then cache purge. Rollback: restore or delete the file.
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/staging4.fuxiaballerinas.com/public_html'
SRC='tools/storefront/mu-plugins/staging4'
cd "$(dirname "$0")/../.."
files=$(git ls-files "$SRC/*.php")
[ -n "$files" ] || { echo "ABORT: no hay plugins en $SRC" >&2; exit 1; }
git diff --quiet HEAD -- "$SRC" || { echo "ABORT: $SRC tiene cambios sin commitear." >&2; exit 1; }
TS=$(date +%Y%m%d-%H%M%S)
"${SSH[@]}" "test \"\$(cd $WP && wp option get home)\" = 'https://staging4.fuxiaballerinas.com'" || { echo "ABORT: el destino no es staging4" >&2; exit 1; }
for f in $files; do
  name=$(basename "$f")
  "${SSH[@]}" "mkdir -p ~/f360-backups/staging4-mu/$TS && cat > ~/f360-backups/staging4-mu/$TS/$name.new" < "$f"
  "${SSH[@]}" "php -l ~/f360-backups/staging4-mu/$TS/$name.new >/dev/null" || { echo "ABORT: $name no pasa php -l; no se instaló." >&2; exit 2; }
  "${SSH[@]}" "if [ -f $WP/wp-content/mu-plugins/$name ]; then cp $WP/wp-content/mu-plugins/$name ~/f360-backups/staging4-mu/$TS/$name.prev; fi; cp ~/f360-backups/staging4-mu/$TS/$name.new $WP/wp-content/mu-plugins/$name"
  echo "instalado en staging4: $name ($(git log -1 --format=%h -- "$f"))"
done
"${SSH[@]}" "cd $WP && wp sg purge >/dev/null 2>&1 || true"
code=$(curl -sL -o /dev/null -w '%{http_code}' "https://staging4.fuxiaballerinas.com/mx/?nc=$TS")
echo "staging4 /mx/ después de instalar: http $code"
[ "$code" = "200" ] || { echo "ATENCIÓN: staging4 no respondió 200. Rollback: ~/f360-backups/staging4-mu/$TS/" >&2; exit 3; }
echo "LISTO. Respaldo: ~/f360-backups/staging4-mu/$TS/"
