#!/usr/bin/env bash
# Prépare en arrière-plan la base E2E jetable et un serveur Next déjà compilé sur le port 3100,
# réutilisé ensuite par e2e.sh (gain : 2-3 min sur le premier test). Lancé par le hook SessionStart.
set -uo pipefail
cd "$(dirname "$0")/../.."
PORT=${E2E_PORT:-3100}
signature=/var/tmp/relais-e2e-serveur.sig
command -v docker >/dev/null && ls /usr/lib/postgresql/*/bin/initdb >/dev/null 2>&1 || exit 0
[[ -f scripts/migrate.mjs ]] || exit 0
eval "$(bash scripts/relais/base-e2e-locale.sh 2>/dev/null)"
[[ -n ${DATABASE_URL:-} && -n ${SESSION_SECRET:-} ]] || exit 0
attendu=$(printf '%s|%s|%s' "$DATABASE_URL" "$SESSION_SECRET" "${HELLOASSO_API_URL:-}" | sha256sum | cut -c1-16)
if curl -s -o /dev/null -m 2 "http://localhost:$PORT" && [[ "$(cat "$signature" 2>/dev/null)" == "$attendu" ]]; then exit 0; fi
setsid npx next dev -p "$PORT" > /var/tmp/relais-e2e-serveur.log 2>&1 < /dev/null &
echo "$attendu" > "$signature"
for _ in $(seq 1 90); do curl -s -o /dev/null -m 5 "http://localhost:$PORT/" && break; sleep 2; done
# Précompilation des pages les plus testées.
for page in / /login /admin/cagnottes /mot-de-passe; do curl -s -o /dev/null -m 120 "http://localhost:$PORT$page" || true; done
