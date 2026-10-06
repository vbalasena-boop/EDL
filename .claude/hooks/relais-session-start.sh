#!/bin/bash
# Démarrage de session Claude Code : dépendances, Codex CLI, puis 2-3 lignes
# d'état pour Claude (file BMAD, autopilote, quota). Sortie courte : chaque
# ligne est lue par Claude et coûte des tokens.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  if [ -f package.json ]; then
    npm install --no-audit --no-fund --silent >/dev/null 2>&1 || echo "⚠️ npm install a échoué."
  fi
  if ! command -v codex >/dev/null 2>&1; then
    npm install -g --silent "@openai/codex@0.159.3" >/dev/null 2>&1 || echo "⚠️ Installation de Codex impossible."
  fi
fi

# File BMAD (stories ouvertes uniquement).
if [ -x scripts/relais/etat.py ] || [ -f scripts/relais/etat.py ]; then
  FILE=$(python3 scripts/relais/etat.py statut 2>/dev/null | head -6)
  if [ -n "$FILE" ]; then
    echo "Relais — stories ouvertes :"
    echo "$FILE"
  else
    echo "Relais — aucune story ouverte."
  fi
fi

# Codex local (pour codex exec depuis la session).
if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
  CODEX="connecté"
else
  CODEX="non connecté (voir « Connexion Codex » dans CLAUDE.md)"
fi

# Tableau de bord de l'autopilote (issue GitHub), si gh est disponible.
TABLEAU=""
if command -v gh >/dev/null 2>&1 && [ -f .github/workflows/autopilote.yml ]; then
  DEPOT=$(git remote get-url origin 2>/dev/null | sed -E 's#^git@[^:]+:#x/#; s#\.git$##' | awk -F/ '{print $(NF-1)"/"$NF}')
  TABLEAU=$(timeout 8 gh api "repos/$DEPOT/issues?labels=relais-tableau&state=open&per_page=1" \
    --jq '.[0] | "\(.html_url) (mis à jour \(.updated_at))"' 2>/dev/null || true)
fi
echo "Codex local : $CODEX. Autopilote : ${TABLEAU:-pas encore de tableau de bord}."

# Quota Claude connu (terminal / app desktop uniquement).
"$(dirname "$0")/relais-quota.sh" 2>/dev/null || true
exit 0
