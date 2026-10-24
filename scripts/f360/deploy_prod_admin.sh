#!/usr/bin/env bash
# Fuxia 360 · the ONLY way this repo deploys the admin (Vercel project "fuxia360", production), approved by Mario as a permission rule.
#   · builds ONE FIXED, REVIEWED commit (F360_DEPLOY_SHA, Mario 2026-10-11 D8) that must be on origin/fuxia-360 — never the tip of
#     the branch, so other sessions' pushed work cannot ride along; it shows the admin-web files and commits it adds over the
#     last production deploy (~/fuxia360-respaldos/prod-admin-deployed.sha) and asks to type the short SHA to confirm;
#   · never uncommitted local files: a clean worktree outside the repo, reset to the exact commit;
#   · no local .env file goes up: the production variables live in Vercel, and the admin's own guard (lib/env-guard.ts)
#     refuses to build if anything points at staging or a server secret is present.
# Rollback: Vercel → fuxia360 → Deployments → previous one → "Promote to Production".
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO="$PWD"
W="${TMPDIR:-/tmp}/f360-admin-prod"
git fetch -q origin fuxia-360
[ -n "${F360_DEPLOY_SHA:-}" ] || { echo "ABORT: indica F360_DEPLOY_SHA=<commit revisado> (ya no se publica la punta de la rama)" >&2; exit 1; }
SHA=$(git rev-parse --verify "${F360_DEPLOY_SHA}^{commit}")
git merge-base --is-ancestor "$SHA" origin/fuxia-360 || { echo "ABORT: $SHA no está en origin/fuxia-360" >&2; exit 1; }
PREV_FILE="$HOME/fuxia360-respaldos/prod-admin-deployed.sha"; PREV=$(cat "$PREV_FILE" 2>/dev/null || echo "")
if [ -n "$PREV" ]; then
  echo "Archivos de admin-web que cambian respecto de lo publicado ($PREV):"; git diff --stat "$PREV" "$SHA" -- admin-web
  echo "Commits incluidos:"; git log --format='  %h %an %s' "$PREV..$SHA" -- admin-web
else
  echo "Sin registro del despliegue anterior: no se puede mostrar la comparación." >&2
fi
read -r -p "Escribe el SHA corto ($(git rev-parse --short "$SHA")) para confirmar: " OK
[ "$OK" = "$(git rev-parse --short "$SHA")" ] || { echo "ABORT: confirmación distinta" >&2; exit 1; }
# macOS purges old temp files, which can leave $W with a gutted .git: re-clone the temp copy when it is not a valid repo
git -C "$W" rev-parse --git-dir >/dev/null 2>&1 || { rm -rf "$W"; git clone -q --no-checkout "$REPO" "$W"; }
git -C "$W" fetch -q "$REPO" "$SHA"
git -C "$W" checkout -q --detach "$SHA"
git -C "$W" reset -q --hard   # macOS can purge files of the temp worktree: always restore the exact commit
git -C "$W" clean -qfdx admin-web -e .vercel
rm -f "$W/admin-web/.env" "$W/admin-web/.env.local" "$W/admin-web/.env.production"
mkdir -p "$W/admin-web/.vercel"
printf '{"projectId":"prj_i204K1Aj52KRUQB0bzmg1nAGx6Yw","orgId":"team_U7bX9aQ3EadSQOVAOKVAhoNj","projectName":"fuxia360"}\n' > "$W/admin-web/.vercel/project.json"
echo "Desplegando el panel de producción desde $(git -C "$W" log --oneline -1)"
cd "$W/admin-web"
for i in 1 2 3; do
  ok=1; out=$(npx -y vercel deploy --prod --yes --scope team_U7bX9aQ3EadSQOVAOKVAhoNj 2>&1) || ok=0
  # Vercel CLI ≥ 62 answers in JSON (no "Production:" line): success = exit 0 + a deployment URL in the answer
  if [ "$ok" = 1 ] && grep -qE "Production:|https://fuxia360-[a-z0-9]+-[a-z0-9-]+\.vercel\.app" <<<"$out"; then
    grep -oE "https://fuxia360-[a-z0-9]+-[a-z0-9-]+\.vercel\.app" <<<"$out" | head -1; echo "LISTO: panel de Fuxia 360 en producción (https://fuxia360.vercel.app)."
    mkdir -p "$(dirname "$PREV_FILE")"; echo "$SHA" > "$PREV_FILE"; exit 0
  fi
  echo "Intento $i no terminó. Lo que dijo Vercel:"; tail -15 <<<"$out"
  sleep 10
done
echo "ATENCIÓN: el despliegue no terminó; revisa Vercel → fuxia360." >&2; exit 2
