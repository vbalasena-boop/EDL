#!/bin/bash
# Démarrage des sessions Claude Code (web) : dépendances du projet + Codex CLI
# pour le relais Claude ↔ Codex (voir CLAUDE.md / AGENTS.md).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Dépendances du projet (tests, lint, build).
if [ -f package.json ]; then
  npm install --no-audit --no-fund --silent >/dev/null 2>&1 || echo "⚠️ npm install a échoué."
fi

# Codex CLI, utilisé avec l'abonnement ChatGPT du fondateur.
CODEX_VERSION="0.159.3"
if ! command -v codex >/dev/null 2>&1; then
  npm install -g --silent "@openai/codex@${CODEX_VERSION}" >/dev/null 2>&1 \
    || echo "⚠️ Installation de Codex impossible."
fi

# État de connexion, transmis à Claude comme contexte de session.
if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
  echo "Codex : installé et connecté. Boucle Codex disponible (section « Boucle Codex » de CLAUDE.md)."
else
  echo "Codex : installé mais non connecté. Au premier besoin, suivre « Connexion Codex » dans CLAUDE.md."
fi
