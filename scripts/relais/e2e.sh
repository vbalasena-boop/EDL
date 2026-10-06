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
npx next dev -p "$PORT" > "$journal" 2>&1 &
serveur=$!
trap 'kill "$serveur" 2>/dev/null || true; pkill -P "$serveur" 2>/dev/null || true' EXIT
for _ in $(seq 1 90); do
    [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" || true)" != 000 ]] && break
    sleep 2
done
E2E_BASE_URL="http://localhost:$PORT" CI=1 npx playwright test "$@" || { echo "--- journal du serveur ---"; tail -n 30 "$journal"; exit 1; }
