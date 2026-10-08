#!/usr/bin/env bash
# Codex dans la session Claude, plusieurs stories indépendantes en parallèle (une worktree chacune).
#   scripts/relais/codex-session.sh lancer <clé> [<clé>...]   → attend la fin, résume chaque story
#   scripts/relais/codex-session.sh appliquer <clé>           → reporte le diff dans le dépôt, retire la worktree
# Aucun commit ni push : Claude relit, vérifie (verifier.sh, E2E) puis commite.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
racine=${RELAIS_WT:-${TMPDIR:-/tmp}/relais-wt}
mkdir -p "$racine"
case ${1:-} in
    lancer)
        shift; (( $# )) || { echo "Usage : $0 lancer <clé>..." >&2; exit 2; }
        pids=()
        for cle in "$@"; do
            wt="$racine/$cle"
            [[ ! -e "$wt" ]] || git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
            git worktree add -q -f --detach "$wt" HEAD
            [[ ! -d node_modules ]] || ln -s "$PWD/node_modules" "$wt/node_modules"
            modele=$(python3 scripts/relais/etat.py meta "$cle" | sed -n 's/^modele=//p')
            fiche=$(python3 scripts/relais/etat.py meta "$cle" | sed -n 's/^fiche=//p')
            ( codex exec --model "$modele" --sandbox workspace-write -C "$wt" \
                "Claude te confie la story $cle (fiche $fiche). Implémente tous les critères, tests ciblés puis bash scripts/relais/verifier.sh. Pas de navigateur, pas de base réelle : Claude lancera les E2E. Mets à jour la section Reprise. Ni commit ni push." \
                > "$racine/$cle.log" 2>&1; echo $? > "$racine/$cle.code" ) &
            pids+=($!)
            echo "→ Codex : $cle ($modele)"
        done
        wait "${pids[@]}" || true
        for cle in "$@"; do
            echo "=== $cle : code $(cat "$racine/$cle.code" 2>/dev/null || echo ?)"
            git -C "$racine/$cle" status --short | head -20
            tail -n 4 "$racine/$cle.log"
        done
        ;;
    appliquer)
        cle=${2:?clé manquante}; wt="$racine/$cle"
        git -C "$wt" add -A
        # sprint-status.yaml : les statuts restent gérés par Claude (etat.py), sinon conflits entre stories parallèles.
        git -C "$wt" diff --cached --binary HEAD -- . ":(exclude)_bmad-output/implementation-artifacts/sprint-status.yaml" | git apply --3way
        git worktree remove --force "$wt"
        echo "Diff de $cle appliqué ; relire puis verifier.sh."
        ;;
    *) echo "Usage : $0 lancer <clé>... | appliquer <clé>" >&2; exit 2 ;;
esac
