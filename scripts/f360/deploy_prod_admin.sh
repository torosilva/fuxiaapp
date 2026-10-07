#!/usr/bin/env bash
# Fuxia 360 · the ONLY way this repo deploys the admin (Vercel project "fuxia360", production), approved by Mario as a permission rule.
#   · builds what is PUSHED on origin/fuxia-360 (never uncommitted local files), in a clean worktree outside the repo;
#   · no local .env file goes up: the production variables live in Vercel, and the admin's own guard (lib/env-guard.ts)
#     refuses to build if anything points at staging or a server secret is present.
# Rollback: Vercel → fuxia360 → Deployments → previous one → "Promote to Production".
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO="$PWD"
W="${TMPDIR:-/tmp}/f360-admin-prod"
git fetch -q origin fuxia-360
SHA=$(git rev-parse origin/fuxia-360)
[ -d "$W/.git" ] || [ -f "$W/.git" ] || git clone -q --no-checkout "$REPO" "$W"
git -C "$W" fetch -q "$REPO" "$SHA"
git -C "$W" checkout -q --detach "$SHA"
git -C "$W" clean -qfdx admin-web -e .vercel
rm -f "$W/admin-web/.env" "$W/admin-web/.env.local" "$W/admin-web/.env.production"
mkdir -p "$W/admin-web/.vercel"
printf '{"projectId":"prj_i204K1Aj52KRUQB0bzmg1nAGx6Yw","orgId":"team_U7bX9aQ3EadSQOVAOKVAhoNj","projectName":"fuxia360"}\n' > "$W/admin-web/.vercel/project.json"
echo "Desplegando el panel de producción desde $(git -C "$W" log --oneline -1)"
cd "$W/admin-web"
for i in 1 2 3; do
  ok=1; out=$(npx -y vercel deploy --prod --yes --scope team_U7bX9aQ3EadSQOVAOKVAhoNj 2>&1) || ok=0
  if [ "$ok" = 1 ] && grep -q "Production:" <<<"$out"; then
    grep -E "Production:" <<<"$out" | head -1; echo "LISTO: panel de Fuxia 360 en producción."; exit 0
  fi
  echo "Intento $i no terminó. Lo que dijo Vercel:"; tail -15 <<<"$out"
  sleep 10
done
echo "ATENCIÓN: el despliegue no terminó; revisa Vercel → fuxia360." >&2; exit 2
