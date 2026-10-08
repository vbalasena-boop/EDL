#!/bin/bash
# StopFailure (rate_limit | billing_error) : la limite Claude vient d'être
# atteinte. Sauvegarde le travail non commité sur une branche claude/wip-*,
# puis lance l'autopilote GitHub pour que Codex prenne la suite sans attendre.
# La sortie de ce hook est ignorée par Claude Code : tout va dans un journal.
set -uo pipefail

ENTREE=$(cat)
ERREUR=$(printf '%s' "$ENTREE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("error") or d.get("error_type") or "")' 2>/dev/null)
case "$ERREUR" in rate_limit|billing_error) ;; *) exit 0 ;; esac

DOSSIER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
JOURNAL="$DOSSIER/relais-limite.log"
MARQUE="$DOSSIER/relais-limite.ts"
mkdir -p "$DOSSIER"
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -f .github/workflows/autopilote.yml ] || exit 0

# Une seule relance par tranche de 30 min (l'erreur se répète à chaque tentative).
MAINTENANT=$(date +%s)
if [ -f "$MARQUE" ] && [ $((MAINTENANT - $(cat "$MARQUE" 2>/dev/null || echo 0))) -lt 1800 ]; then
  exit 0
fi
echo "$MAINTENANT" > "$MARQUE"

{
  echo "== $(date '+%F %T') limite Claude ($ERREUR)"

  # Travail non commité → instantané poussé sur une branche à part, via un
  # index temporaire : ni l'arbre de travail ni l'index réel ne bougent.
  # git add -A respecte .gitignore (.env.local et autres secrets restent locaux).
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    INDEX=$(mktemp)
    cp "$(git rev-parse --git-dir)/index" "$INDEX" 2>/dev/null || true
    GIT_INDEX_FILE="$INDEX" git add -A >/dev/null 2>&1
    ARBRE=$(GIT_INDEX_FILE="$INDEX" git write-tree)
    COMMIT=$(git commit-tree "$ARBRE" -p HEAD -m "WIP Claude : limite d'usage atteinte (sauvegarde automatique)")
    BRANCHE="claude/wip-$(date +%Y%m%d-%H%M)"
    timeout 30 git push -q origin "$COMMIT:refs/heads/$BRANCHE" && echo "WIP sauvegardé sur $BRANCHE"
    rm -f "$INDEX"
  fi

  # Story que Claude avait en main (une seule) → l'autopilote la reprend en priorité.
  STORY=$(python3 scripts/relais/etat.py statut 2>/dev/null | awk -F' : ' '/in-progress · claude$/ {print $1}')
  [ "$(printf '%s\n' "$STORY" | grep -c .)" = "1" ] || STORY=""

  timeout 30 scripts/relais/lancer-autopilote.sh limite-claude tous "$STORY"
} >> "$JOURNAL" 2>&1

exit 0
