#!/usr/bin/env bash
# Lance les specs Playwright données contre un serveur Next local.
# Usage : scripts/relais/e2e.sh e2e/a.spec.ts [e2e/b.spec.ts ...]
set -euo pipefail
(( $# )) || exit 0
PORT=${E2E_PORT:-3100}
if [[ -z "${PLAYWRIGHT_CHROMIUM_PATH:-}" && ! -d "${PLAYWRIGHT_BROWSERS_PATH:-/nonexistent}" ]]; then
    npx playwright install --with-deps chromium > /dev/null 2>&1 || npx playwright install chromium > /dev/null
fi
journal=$(mktemp)
signature=$(printf '%s|%s|%s' "${DATABASE_URL:-}" "${SESSION_SECRET:-}" "${HELLOASSO_API_URL:-}" | sha256sum | cut -c1-16)
if curl -s -o /dev/null -m 2 "http://localhost:$PORT"; then
    # Serveur préchauffé par serveur-e2e.sh avec la même base et le même secret : on le réutilise.
    if [[ "$(cat /var/tmp/relais-e2e-serveur.sig 2>/dev/null)" == "$signature" ]]; then
        journal=/var/tmp/relais-e2e-serveur.log
    else
        # Un autre serveur (autre base, autre secret) fausserait les résultats : refuser.
        echo "Port $PORT déjà utilisé par un autre serveur : arrêtez-le (fuser -k $PORT/tcp) avant les E2E." >&2
        exit 1
    fi
else
    # Groupe de processus dédié : arrêter npx ne suffit pas, next-server est un petit-enfant.
    setsid npx next dev -p "$PORT" > "$journal" 2>&1 &
    serveur=$!
    trap 'kill -- -"$serveur" 2>/dev/null || kill "$serveur" 2>/dev/null || true' EXIT
fi
for _ in $(seq 1 90); do
    [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" || true)" != 000 ]] && break
    sleep 2
done
E2E_BASE_URL="http://localhost:$PORT" CI=1 npx playwright test "$@" || { echo "--- journal du serveur ---"; tail -n 30 "$journal"; exit 1; }
