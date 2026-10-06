#!/usr/bin/env bash
# Active l'autopilote sur plusieurs dépôts en une fois (à lancer sur le Mac du fondateur).
# Pour chaque dépôt : connexion Codex dédiée → secret CODEX_AUTH_CI, secret RELAIS_PAT,
# autorisation des PR par GitHub Actions, suppression de l'ancien secret CODEX_AUTH_JSON.
# Prérequis : gh (brew install gh && gh auth login) et codex (npm i -g @openai/codex).
# Usage : scripts/relais/activer-projets.sh [propriétaire/dépôt ...]
set -euo pipefail

DEPOTS=("$@")
if (( ${#DEPOTS[@]} == 0 )); then
    DEPOTS=(vbalasena-boop/asso-manager vbalasena-boop/kado vbalasena-boop/Restaurant vbalasena-boop/pro-loc
            vbalasena-boop/prospection-insta-facebook vbalasena-boop/monkey-pro vbalasena-boop/EDL)
fi

gh auth status >/dev/null 2>&1 || { echo "Connecte d'abord gh : gh auth login"; exit 1; }
command -v codex >/dev/null || { echo "Installe d'abord Codex : npm i -g @openai/codex"; exit 1; }

echo "Jeton RELAIS_PAT : jeton fin GitHub avec « Secrets : Read and write » sur TOUS ces dépôts"
echo "(https://github.com/settings/personal-access-tokens/new). Laisse vide pour ne pas le changer."
read -r -s -p "Colle le jeton (rien ne s'affiche) : " PAT; echo

for depot in "${DEPOTS[@]}"; do
    echo; echo "=== $depot"
    secrets=$(gh secret list --repo "$depot" --json name --jq '.[].name' 2>/dev/null || true)
    if grep -qx CODEX_AUTH_CI <<<"$secrets" && (( $# == 0 )); then
        echo "Connexion Codex déjà en place (relancer avec ce seul dépôt en argument pour la refaire)."
    else
        dossier="$HOME/.codex-ci-${depot##*/}"
        mkdir -p "$dossier" && chmod 700 "$dossier"
        echo "Connexion Codex dédiée à $depot : ouvre le lien et entre le code."
        CODEX_HOME="$dossier" codex login --device-auth
        base64 < "$dossier/auth.json" | gh secret set CODEX_AUTH_CI --repo "$depot"
        echo "✓ CODEX_AUTH_CI"
    fi
    if [[ -n "$PAT" ]]; then
        printf '%s' "$PAT" | gh secret set RELAIS_PAT --repo "$depot" && echo "✓ RELAIS_PAT"
    fi
    gh api -X PUT "repos/$depot/actions/permissions/workflow" -f default_workflow_permissions=read \
        -F can_approve_pull_request_reviews=true >/dev/null && echo "✓ PR autorisées pour GitHub Actions"
    if grep -qx CODEX_AUTH_JSON <<<"$secrets"; then
        gh secret delete CODEX_AUTH_JSON --repo "$depot" && echo "✓ ancien secret CODEX_AUTH_JSON supprimé"
    fi
done

echo; echo "Terminé. Chaque dossier ~/.codex-ci-<dépôt> est réservé à la CI : ne plus l'utiliser ailleurs."
