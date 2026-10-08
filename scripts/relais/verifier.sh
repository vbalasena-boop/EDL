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
    code=0
    bash -o pipefail -c "$commande" > "$log" 2>&1 || code=$?
    if (( code != 0 )) && [[ "$commande" == *"tsc"* && -d .next ]] && ! grep -E '^[^ ].*error TS' "$log" | grep -qv '^\.next/'; then
        # Erreurs uniquement dans les types générés par un serveur `next dev` en cours d'écriture
        # (serveur E2E préchauffé) : on les régénère plutôt que d'échouer à tort.
        rm -rf .next/dev/types .next/types
        code=0
        bash -o pipefail -c "$commande" > "$log" 2>&1 || code=$?
    fi
    if (( code != 0 )); then
        echo "Échec : $commande" >&2
        tail -n 60 "$log" >&2
        exit "$code"
    fi
done
