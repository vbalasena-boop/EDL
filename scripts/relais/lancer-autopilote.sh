#!/bin/bash
# Lance l'autopilote GitHub (autopilote.yml) sans attendre son résultat.
# Usage : scripts/relais/lancer-autopilote.sh [declencheur] [pour] [story]
#   declencheur : manuel | relais | limite-claude   (défaut : manuel)
#   pour        : codex | tous                       (défaut : codex)
# Utilise `gh api` (client GitHub de Claude Code en cloud, ou gh CLI en local).
set -euo pipefail

DECLENCHEUR="${1:-manuel}"
POUR="${2:-codex}"
STORY="${3:-}"

cd "$(git rev-parse --show-toplevel)"
DEPOT=$(git remote get-url origin | sed -E 's#^git@[^:]+:#x/#; s#\.git$##' | awk -F/ '{print $(NF-1)"/"$NF}')

if ! command -v gh >/dev/null 2>&1; then
  echo "Autopilote non lancé : gh introuvable. Lance-le depuis GitHub → Actions → Autopilote → Run workflow."
  exit 1
fi

BRANCHE=$(gh api "repos/$DEPOT" --jq .default_branch)
python3 -c 'import json,sys; print(json.dumps({"ref": sys.argv[1], "inputs": {"declencheur": sys.argv[2], "pour": sys.argv[3], "story": sys.argv[4]}}))' \
  "$BRANCHE" "$DECLENCHEUR" "$POUR" "$STORY" \
  | gh api -X POST "repos/$DEPOT/actions/workflows/autopilote.yml/dispatches" --input - >/dev/null

echo "Autopilote lancé ($DECLENCHEUR, pour=$POUR${STORY:+, story=$STORY}) : https://github.com/$DEPOT/actions/workflows/autopilote.yml"
