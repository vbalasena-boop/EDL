#!/usr/bin/env bash
set -euo pipefail
log=$(mktemp)
trap 'rm -f "$log"' EXIT
commandes=()
if [[ -f .relais/verifier ]]; then
    while IFS= read -r ligne || [[ -n "$ligne" ]]; do
        [[ "$ligne" =~ ^[[:space:]]*(#|$) ]] || commandes+=("$ligne")
    done < .relais/verifier
elif [[ -f package.json ]]; then
    commandes+=("npm test")
    if node -e 'process.exit(require("./package.json").scripts?.lint ? 0 : 1)'; then commandes+=("npm run lint"); fi
    [[ ! -f tsconfig.json ]] || commandes+=("npx tsc --noEmit")
fi
for commande in "${commandes[@]}"; do
    echo "Vérification : $commande"
    if bash -o pipefail -c "$commande" > "$log" 2>&1; then
        :
    else
        code=$?
        echo "Échec : $commande" >&2
        tail -n 60 "$log" >&2
        exit "$code"
    fi
done
