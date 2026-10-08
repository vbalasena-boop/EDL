#!/usr/bin/env bash
# Base Postgres jetable + proxy HTTP Neon local, pour les E2E qui écrivent en base (jamais la production).
# Usage local : source <(scripts/relais/base-e2e-locale.sh) puis bash scripts/relais/e2e.sh e2e/<spec>.ts
# Usage GitHub Actions : bash scripts/relais/base-e2e-locale.sh --github
set -euo pipefail
if [[ ${1:-} == --github ]]; then
  docker run -d --rm --name relais-e2e-postgres --network host \
    -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=neondb \
    postgres:16 >/dev/null
  pret=false
  for _ in $(seq 1 30); do
    if docker exec relais-e2e-postgres pg_isready -U postgres -d neondb >/dev/null 2>&1; then pret=true; break; fi
    sleep 1
  done
  [[ $pret == true ]] || { echo 'Postgres E2E indisponible' >&2; exit 1; }
else
  S=/var/tmp/pg-e2e; P=$(ls -d /usr/lib/postgresql/*/bin | tail -1)
  if ! su postgres -c "$P/pg_isready -h 127.0.0.1 -p 5432" >/dev/null 2>&1; then
    rm -rf $S; mkdir -p $S; chown postgres $S
    su postgres -c "$P/initdb -D $S/data -U postgres --auth=trust >/dev/null"
    su postgres -c "$P/pg_ctl -D $S/data -o '-k $S -p 5432 -c listen_addresses=127.0.0.1' -l $S/log start >/dev/null"
    su postgres -c "psql -h 127.0.0.1 -qc \"alter user postgres password 'postgres'\" -c 'create database neondb'" >/dev/null
  fi
  docker info >/dev/null 2>&1 || { (nohup dockerd >/var/tmp/dockerd.log 2>&1 &); sleep 8; }
fi
docker inspect neon-proxy >/dev/null 2>&1 || docker run -d --rm --name neon-proxy --network host \
  -e PG_CONNECTION_STRING=postgres://postgres:postgres@127.0.0.1:5432/neondb \
  ghcr.io/timowilhelm/local-neon-http-proxy:main >/dev/null
# Le proxy met quelques secondes à accepter les requêtes : attendre avant de migrer.
pret=false
for _ in $(seq 1 30); do
  if curl -sf -m 2 -X POST localhost:4444/sql -H 'Neon-Connection-String: postgres://postgres:postgres@db.localtest.me:5432/neondb' \
    -d '{"query":"select 1","params":[]}' >/dev/null; then pret=true; break; fi
  sleep 1
done
[[ $pret == true ]] || { echo 'Proxy Neon E2E indisponible' >&2; exit 1; }
cat <<VARS
export NEON_FETCH_ENDPOINT=http://localhost:4444/sql
export DATABASE_URL=postgres://postgres:postgres@db.localtest.me:5432/neondb
export SESSION_SECRET=e2e-local-base-jetable-0123456789abcdef0123456789
export HELLOASSO_API_URL=http://127.0.0.1:4466
export PLAYWRIGHT_CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)
VARS
[[ ! -f "$(dirname "$0")/../migrate.mjs" ]] || (cd "$(dirname "$0")/../.." && NEON_FETCH_ENDPOINT=http://localhost:4444/sql DATABASE_URL=postgres://postgres:postgres@db.localtest.me:5432/neondb node scripts/migrate.mjs >&2)
