#!/usr/bin/env bash
set -euo pipefail
source .relais/config
export RUNNER_TEMP=${RUNNER_TEMP:-${TMPDIR:-/tmp}/relais-local-$$}
mkdir -p "$RUNNER_TEMP"
state="$RUNNER_TEMP/relais.env"
[[ ! -f "$state" ]] || source "$state"
export GH_TOKEN=${GH_TOKEN:-${GITHUB_TOKEN:-}}
export CODEX_HOME="$RUNNER_TEMP/codex"
export DECLENCHEUR=${DECLENCHEUR:-manuel} POUR=${POUR:-codex} PROFONDEUR=${PROFONDEUR:-0}
export STORY=${STORY:-} MODE=${MODE:-} MODELE=${MODELE:-} FICHE=${FICHE:-} EPIC=${EPIC:-}
export GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-$PWD} GITHUB_RUN_ID=${GITHUB_RUN_ID:-local}
etat() { python3 scripts/relais/etat.py "$@"; }
out() {
    local key=$1 value=${2:-} upper=${1^^}
    [[ "$value" != *$'\n'* ]] || return 1
    printf '%s=%s\n' "$key" "$value" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    printf 'export %s=%q\n' "$upper" "$value" >> "$state"
    printf -v "$upper" '%s' "$value"
    export "$upper"
}
stop() { out go false; out raison "$1"; }
board() {
    if [[ -n ${GITHUB_REPOSITORY:-} && -n $GH_TOKEN ]]; then
        gh issue list --repo "$GITHUB_REPOSITORY" --label relais-tableau --state open --json number,body --limit 1 > "$RUNNER_TEMP/tableau.json"
    else printf '[]\n' > "$RUNNER_TEMP/tableau.json"; fi
}
marker() {
    python3 - "$RUNNER_TEMP/tableau.json" "$1" <<'PY'
import json,re,sys
items=json.load(open(sys.argv[1]))
m=re.search(r'<!--\s*'+sys.argv[2]+r'=(\d+)\s*-->', items[0]['body'] if items else '')
print(m[1] if m else 0)
PY
}
apercu() {
    # Lien de déploiement d'aperçu (Vercel publie un « deployment » GitHub par commit), 4 min max.
    local sha=$1 id url
    [[ "${GITHUB_ACTIONS:-}" == true ]] || return 0
    for _ in $(seq 1 24); do
        id=$(gh api "repos/$GITHUB_REPOSITORY/deployments?sha=$sha&per_page=1" --jq '.[0].id // empty' 2>/dev/null || true)
        if [[ -n "$id" ]]; then
            url=$(gh api "repos/$GITHUB_REPOSITORY/deployments/$id/statuses" --jq '[.[] | select(.state == "success")][0].environment_url // empty' 2>/dev/null || true)
            [[ -z "$url" ]] || { echo "$url"; return 0; }
        fi
        sleep 10
    done
}
default_branch() { gh repo view "$GITHUB_REPOSITORY" --json defaultBranchRef --jq .defaultBranchRef.name; }
commit() {
    git add -A
    if ! git diff --cached --quiet; then git commit -m "$1"; fi
}
push_default() {
    local essai
    for essai in 1 2 3; do
        if git pull --no-rebase && git push; then return 0; fi
        [[ ! -f $(git rev-parse --git-path MERGE_HEAD) ]] || return 1
    done
    return 1
}
case ${1:-} in
    decider)
        : > "$state"
        [[ "$PROFONDEUR" =~ ^[0-9]+$ ]] || { stop profondeur-invalide; exit 0; }
        [[ "$POUR" == codex || "$POUR" == tous ]] || { stop pour-invalide; exit 0; }
        if [[ "${SECRET_CODEX:-true}" == false ]]; then out alerte_auth secret-manquant; stop secret-manquant; exit 0; fi
        board
        now=$(date +%s)
        if (( now < $(marker reprise_codex_apres) )); then stop quota-codex; exit 0; fi
        if (( now < $(marker pour_tous_jusqua) )); then POUR=tous; fi
        out pour "$POUR"
        if [[ "$DECLENCHEUR" == schedule ]]; then
            dernier=$(git log -1 --format=%ct --grep='^Claude-Session:')
            if [[ -n "$dernier" ]] && (( now - dernier < SEUIL_CLAUDE_MINUTES * 60 )); then stop claude-actif; exit 0; fi
        fi
        if [[ "$POUR" == codex && "${PRENDRE_CLAUDE_SI_INACTIF:-oui}" == oui ]]; then
            dernier=$(git log -1 --format=%ct --grep='^Claude-Session:')
            if [[ -z "$dernier" ]] || (( now - dernier >= SEUIL_CLAUDE_MINUTES * 60 )); then POUR=tous; out pour tous; fi
        fi
        if (( PROFONDEUR >= MAX_ENCHAINEMENTS )); then stop chaine-max; exit 0; fi
        STORY=${STORY:-$(etat prochaine --pour "$POUR" --seuil "$SEUIL_ARRET_MINUTES")}
        if [[ -z "$STORY" ]]; then
            EPIC=$(etat epic-a-planifier)
            if [[ "$PLANIFIER_AUTO" == oui && -n "$EPIC" ]]; then
                out mode planifier; out epic "$EPIC"; out story ''; out fiche ''; out modele gpt-6-astra; out statut_initial ''
            else stop rien-a-faire; exit 0; fi
        else
            etat meta "$STORY" > "$RUNNER_TEMP/meta"
            if grep -qx 'statut=done' "$RUNNER_TEMP/meta"; then stop deja-faite; exit 0; fi
            while IFS='=' read -r key value; do
                case "$key" in statut) out statut_initial "$value" ;; agent) out agent_initial "$value" ;; fiche|modele) out "$key" "$value" ;; esac
            done < "$RUNNER_TEMP/meta"
            out story "$STORY"; out epic ''
            if [[ "$STATUT_INITIAL" == review ]]; then out mode revue; else out mode implementer; fi
        fi
        out go true; out raison "$MODE"
        ;;
    marquer)
        if [[ "$MODE" == implementer ]]; then
            etat passer "$STORY" in-progress --agent autopilote
            commit "Autopilote : $STORY → in-progress"
            push_default
        fi
        ;;
    codex)
        out codex_ok false; out quota_atteint false; out auth_ko false
        if [[ -z ${CODEX_AUTH_JSON:-} ]]; then out alerte_auth secret-manquant; out auth_ko true; exit 0; fi
        umask 077
        mkdir -p "$CODEX_HOME"
        # Une seule restauration par run : Codex peut avoir déjà fait tourner le jeton (story précédente de la boucle).
        if [[ ! -f "$CODEX_HOME/auth.json" ]]; then
            if ! printf '%s' "$CODEX_AUTH_JSON" | base64 --decode > "$CODEX_HOME/auth.json"; then
                out auth_ko true; out alerte_auth secret-invalide; exit 0
            fi
            chmod 600 "$CODEX_HOME/auth.json"
            sha256sum "$CODEX_HOME/auth.json" | cut -d ' ' -f 1 > "$RUNNER_TEMP/auth.sha256"
        fi
        case "$MODE" in
            implementer) prompt="L'autopilote te confie la story BMAD $STORY : elle t'appartient, le verrou « un agent par story » d'AGENTS.md ne s'applique pas à toi. Fiche : $FICHE. Implémente tous les critères d'acceptation, en respectant AGENTS.md. Lance les tests ciblés (unitaires). Ne lance pas les tests E2E Playwright : ton bac à sable n'a pas de navigateur, l'autopilote les lance après toi. Coche les critères faits et mets à jour la section Reprise de la fiche. Ne modifie pas sprint-status.yaml. Ni commit ni push." ;;
            revue) prompt="L'autopilote te confie la story BMAD $STORY : elle t'appartient, le verrou « un agent par story » d'AGENTS.md ne s'applique pas à toi. Relis le travail de la story $STORY (fiche $FICHE ; commits : git log --oneline --grep $STORY) contre ses critères d'acceptation. Corrige tout défaut ou critère manquant. Mets à jour la Reprise. Ni commit ni push. Si tout est bon, ne change rien au code." ;;
            planifier) prompt="L'autopilote te confie la planification de l'epic $EPIC. Cet epic est validé mais n'a plus de story ouverte. À partir des documents de _bmad-output/planning-artifacts/ qui le concernent, écris jusqu'à 5 prochaines stories (≤ 1 h chacune), chacune dans _bmad-output/implementation-artifacts/spec-<clé>.md avec **Agent :** (codex, ou claude si elle exige base de données, migrations, sécurité, paiements ou outils de production), **Niveau :** (simple|moyen|complexe), **Priorité :** (haute|normale|basse), objectif, critères d'acceptation vérifiables, fichiers concernés, section Reprise ; ajoute-les en ready-for-dev dans development_status, sous l'epic. Ne code rien. Si les documents montrent que tout l'epic est déjà livré, n'écris aucune story : passe $EPIC en done et $EPIC-retrospective en done dans development_status, et écris la rétrospective dans _bmad-output/implementation-artifacts/$EPIC-retro-$(date +%Y-%m-%d).md (livré, ce qui a coincé d'après les sections Reprise et les échecs de l'autopilote, PR encore ouvertes, 3 actions). Ni commit ni push." ;;
            *) exit 1 ;;
        esac
        if env -u CODEX_AUTH_JSON -u RELAIS_PAT -u GH_TOKEN -u GITHUB_TOKEN codex exec --json --model "$MODELE" --sandbox workspace-write -C "$GITHUB_WORKSPACE" "$prompt" > "$RUNNER_TEMP/codex.jsonl" 2> "$RUNNER_TEMP/codex.err"; then out codex_ok true; fi
        # Relecture dans le même run (évite un second démarrage complet de la CI).
        if [[ "$MODE" == implementer && "$CODEX_OK" == true ]]; then
            relecture="L'autopilote te confie la relecture de la story BMAD $STORY (fiche $FICHE) : elle t'appartient. Relis les modifications non commitées (git status, git diff, nouveaux fichiers) contre chaque critère d'acceptation. Corrige tout défaut ou critère manquant ; sinon ne change rien. Ne lance pas les tests E2E Playwright : ton bac à sable n'a pas de navigateur, l'autopilote les lance après toi. Mets à jour la Reprise. Ni commit ni push."
            if ! env -u CODEX_AUTH_JSON -u RELAIS_PAT -u GH_TOKEN -u GITHUB_TOKEN codex exec --json --model "$MODELE" --sandbox workspace-write -C "$GITHUB_WORKSPACE" "$relecture" >> "$RUNNER_TEMP/codex.jsonl" 2>> "$RUNNER_TEMP/codex.err"; then
                echo "Relecture Codex en échec : la story passera en review pour une relecture ultérieure."
                out relecture_ok false
            else out relecture_ok true; fi
        fi
        echo "--- Codex : fin de sortie (diagnostic) ---"
        tail -n 25 "$RUNNER_TEMP/codex.err" | cut -c1-400 || true
        python3 - "$RUNNER_TEMP/codex.jsonl" <<'PY2' || true
import json, sys
for ligne in open(sys.argv[1]).read().splitlines()[-200:]:
    try:
        e = json.loads(ligne)
    except ValueError:
        continue
    t = e.get("type", "")
    item = e.get("item") or {}
    if t in ("error", "turn.failed"):
        print(t, json.dumps(e.get("error") or e.get("message"), ensure_ascii=False)[:400])
    elif t == "item.completed" and item.get("type") in ("agent_message", "error"):
        print(item.get("type"), str(item.get("text") or item.get("message"))[:400])
    elif t == "item.completed" and item.get("type") == "command_execution" and item.get("exit_code") not in (0, None):
        print("commande", item.get("exit_code"), str(item.get("command"))[:150], str(item.get("aggregated_output"))[-200:])
PY2
        if grep -qi 'hit your usage limit' "$RUNNER_TEMP/codex.jsonl" "$RUNNER_TEMP/codex.err"; then out quota_atteint true; fi
        # Erreur d'authentification seulement si Codex a échoué (un « 401 » peut apparaître dans du code ou des tests).
        if [[ "$CODEX_OK" != true ]] && grep -Eqi 'refresh_token_reused|refresh token|401 Unauthorized|Not signed in|please log in' "$RUNNER_TEMP/codex.err" "$RUNNER_TEMP/codex.jsonl"; then out auth_ko true; fi
        while IFS='=' read -r key value; do out "$key" "$value"; done < <(etat quota-codex "$CODEX_HOME")
        ;;
    sauver-auth)
        trap 'python3 -c '\''import os,shutil; shutil.rmtree(os.environ["CODEX_HOME"],ignore_errors=True)'\''' EXIT
        if [[ -f "$CODEX_HOME/auth.json" && -f "$RUNNER_TEMP/auth.sha256" ]]; then
            actuel=$(sha256sum "$CODEX_HOME/auth.json" | cut -d ' ' -f 1)
            if [[ "$actuel" != "$(cat "$RUNNER_TEMP/auth.sha256")" ]]; then
                if [[ -n ${RELAIS_PAT:-} ]]; then
                    if ! base64 -w0 "$CODEX_HOME/auth.json" | GH_TOKEN="$RELAIS_PAT" gh secret set CODEX_AUTH_CI --repo "$GITHUB_REPOSITORY" > "$RUNNER_TEMP/auth-save.log" 2>&1; then
                        out alerte_auth sauvegarde-echouee; out auth_ko true
                    fi
                else out alerte_auth pat-manquant; out auth_ko true; fi
            fi
        fi
        ;;
    publier)
        out resultat publication-en-cours
        if [[ -z $(git status --porcelain) && ( ${QUOTA_ATTEINT:-false} == true || ${AUTH_KO:-false} == true ) ]]; then
            if [[ -n "$STORY" ]]; then
                etat passer "$STORY" "$STATUT_INITIAL" --agent "${AGENT_INITIAL:-codex}"
                commit "Autopilote : $STORY interrompue"
                push_default
            fi
            out resultat interrompu; exit 0
        fi
        sensible=false; code_modifie=false
        while IFS= read -r -d '' fichier; do
            case "$fichier" in _bmad-output/implementation-artifacts/spec-*.md|_bmad-output/implementation-artifacts/sprint-status.yaml) continue ;; esac
            code_modifie=true
            for prefixe in $CHEMINS_SENSIBLES; do [[ "$fichier" != "$prefixe"* ]] || sensible=true; done
        done < <({ git diff --name-only -z --no-renames HEAD; git ls-files --others --exclude-standard -z; })
        # Implémentation sans aucun changement de code = échec (Codex a refusé ou n'a rien fait).
        if [[ "$MODE" == implementer && "$code_modifie" == false ]]; then CODEX_OK=false; fi
        # Rien de modifié et Codex en échec : pas de PR vide, seulement l'échec noté dans la fiche.
        if [[ "$code_modifie" == false && ${CODEX_OK:-false} != true && -n "$STORY" ]]; then
            git checkout -- _bmad-output/implementation-artifacts/ 2>/dev/null || true
            SANS_PR=true
        fi
        # Story réservée à Claude faite par Codex : toujours en PR, Claude valide.
        [[ "${AGENT_INITIAL:-}" != claude ]] || sensible=true
        verification=false
        if [[ "$MODE" == planifier ]]; then
            if etat statut > "$RUNNER_TEMP/verifier.log" 2>&1; then verification=true; fi
        elif [[ ${SANS_PR:-false} != true ]] && env -u GH_TOKEN -u GITHUB_TOKEN scripts/relais/verifier.sh > "$RUNNER_TEMP/verifier.log" 2>&1; then verification=true; fi
        # Tests E2E des specs écrits ou modifiés par la story (les autres peuvent exiger la base de données).
        if [[ "$verification" == true && -x scripts/relais/e2e.sh ]]; then
            # Specs modifiés par la story + specs cités dans sa fiche (critères d'acceptation).
            mapfile -t specs < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; [[ -z "$FICHE" ]] || grep -oE 'e2e/[A-Za-z0-9._/-]+\.spec\.ts' "$FICHE"; } | grep -E '^e2e/.*\.spec\.ts$' | sort -u | while read -r f; do [[ -f "$f" ]] && echo "$f"; done)
            if (( ${#specs[@]} )); then
                if env -u GH_TOKEN -u GITHUB_TOKEN scripts/relais/e2e.sh "${specs[@]}" >> "$RUNNER_TEMP/verifier.log" 2>&1; then echo "E2E OK : ${specs[*]}"
                else verification=false; echo "E2E en échec : ${specs[*]}"; fi
            fi
        fi
        out verification_ok "$verification"; out sensible "$sensible"
        if [[ ${CODEX_OK:-false} == true && "$verification" == true && "$sensible" == false ]]; then
            if [[ "$MODE" == implementer && ${RELECTURE_OK:-false} == true ]]; then etat passer "$STORY" done; verbe="implémentée et relue"
            elif [[ "$MODE" == implementer ]]; then etat passer "$STORY" review; verbe=implémentée
            elif [[ "$MODE" == revue ]]; then etat passer "$STORY" done; verbe=relue
            else verbe=planifiée; fi
            commit "Autopilote : ${STORY:-$EPIC} $verbe (Codex $MODELE)"
            push_default
            out resultat "$verbe"
        else
            raison="codex=${CODEX_OK:-false}, vérification=$verification, sensible=$sensible"
            [[ "$code_modifie" == true ]] || raison="$raison, aucun changement de code"
            branche_defaut=$(default_branch)
            if [[ ${SANS_PR:-false} == true ]]; then
                : > "$RUNNER_TEMP/verifier.log"
            else
            branche="autopilote/${STORY:-$EPIC}-$GITHUB_RUN_ID"
            git switch -c "$branche"
            if [[ -z $(git status --porcelain) ]]; then
                mkdir -p _bmad-output/implementation-artifacts
                printf 'Autopilote : run %s, %s\n' "$GITHUB_RUN_ID" "$raison" > "_bmad-output/implementation-artifacts/autopilote-$GITHUB_RUN_ID.md"
            fi
            commit "Autopilote : ${STORY:-$EPIC} à vérifier (Codex $MODELE)"
            git push -u origin "$branche"
            { printf 'Raison : %s\n\nDernières lignes du contrôle :\n```text\n' "$raison"; tail -n 40 "$RUNNER_TEMP/verifier.log"; printf '\n```\n'; } > "$RUNNER_TEMP/pr.md"
            url_pr=$(gh pr create --repo "$GITHUB_REPOSITORY" --draft --base "$branche_defaut" --head "$branche" --title "Autopilote : ${STORY:-$EPIC} à vérifier" --body-file "$RUNNER_TEMP/pr.md") \
                || url_pr="ouvrir la PR en un clic : https://github.com/$GITHUB_REPOSITORY/compare/$branche_defaut...$branche?expand=1"
            lien=$(apercu "$(git rev-parse HEAD)")
            echo "- PR brouillon à valider (${STORY:-$EPIC}, $raison) : $url_pr${lien:+ · à tester sur ton téléphone : $lien}" >> "$RUNNER_TEMP/notifs"
            git switch "$branche_defaut"
            fi
            if [[ -n "$STORY" ]]; then
                if [[ "$sensible" == true && "$verification" == true ]]; then etat passer "$STORY" review --agent claude
                else
                    echecs=$(python3 - "$FICHE" "$GITHUB_RUN_ID" "$raison" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); texte=p.read_text()
n=len(re.findall(r'^- Autopilote : échec \d+',texte,re.M))+1
ligne=f'- Autopilote : échec {n} (run {sys.argv[2]}, {sys.argv[3]})\n'
m=re.search(r'^## Reprise\s*$',texte,re.M)
if m: texte=texte[:m.end()]+'\n'+ligne+texte[m.end():]
else: texte+='\n## Reprise\n\n'+ligne
p.write_text(texte); print(n)
PY
)
                    if (( echecs >= MAX_ECHECS )); then etat passer "$STORY" "$STATUT_INITIAL" --agent claude; echo "- Story $STORY rendue à Claude après $echecs échecs" >> "$RUNNER_TEMP/notifs"
                    else etat passer "$STORY" "$STATUT_INITIAL" --agent "${AGENT_INITIAL:-codex}"; fi
                fi
                commit "Autopilote : $STORY état après PR"
                push_default
            fi
            if [[ ${SANS_PR:-false} == true ]]; then out resultat echec-sans-changement; else out resultat pr-brouillon; fi
        fi
        ;;
    tableau)
        [[ -n ${GITHUB_REPOSITORY:-} && -n "$GH_TOKEN" ]] || { echo 'Tableau indisponible hors GitHub'; exit 0; }
        board
        etat statut > "$RUNNER_TEMP/file.txt"
        python3 scripts/relais/tableau.py "$RUNNER_TEMP"
        numero=$(cat "$RUNNER_TEMP/issue-number")
        if [[ -n "$numero" ]]; then
            gh issue edit "$numero" --repo "$GITHUB_REPOSITORY" --title '🛰️ Relais — tableau de bord' --body-file "$RUNNER_TEMP/tableau.md"
        else
            gh label create relais-tableau --repo "$GITHUB_REPOSITORY" --color 1D76DB --force
            gh issue create --repo "$GITHUB_REPOSITORY" --label relais-tableau --title '🛰️ Relais — tableau de bord' --body-file "$RUNNER_TEMP/tableau.md"
        fi
        # Notification sur le téléphone (application GitHub) : mention du propriétaire, seulement si une action est attendue.
        [[ -z ${ALERTE_AUTH:-} ]] || echo "- Alerte connexion Codex : $ALERTE_AUTH (voir le tableau)" >> "$RUNNER_TEMP/notifs"
        [[ ${QUOTA_ATTEINT:-false} != true ]] || echo "- Quota Codex atteint : reprise automatique après le reset" >> "$RUNNER_TEMP/notifs"
        if [[ -s "$RUNNER_TEMP/notifs" ]]; then
            cible=${numero:-$(gh issue list --repo "$GITHUB_REPOSITORY" --label relais-tableau --state open --json number --jq '.[0].number')}
            { echo "@${GITHUB_REPOSITORY_OWNER:-${GITHUB_REPOSITORY%%/*}} action attendue :"; sort -u "$RUNNER_TEMP/notifs"; } > "$RUNNER_TEMP/notif.md"
            gh issue comment "$cible" --repo "$GITHUB_REPOSITORY" --body-file "$RUNNER_TEMP/notif.md" || true
        fi
        for label in veilleur rappel-token; do
            while IFS= read -r numero; do
                [[ -z "$numero" ]] || gh issue close "$numero" --repo "$GITHUB_REPOSITORY" --comment "Remplacé par l'autopilote"
            done < <(gh issue list --repo "$GITHUB_REPOSITORY" --state open --label "$label" --json number --jq '.[].number')
        done
        ;;
    enchainer)
        if [[ ${GO:-false} != true || ${QUOTA_ATTEINT:-false} == true || ${AUTH_KO:-false} == true ]]; then exit 0; fi
        if (( PROFONDEUR + 1 >= MAX_ENCHAINEMENTS )); then exit 0; fi
        prochaine=$(etat prochaine --pour "$POUR" --seuil "$SEUIL_ARRET_MINUTES")
        epic=''
        [[ "$PLANIFIER_AUTO" != oui ]] || epic=$(etat epic-a-planifier)
        if [[ -n "$prochaine" || -n "$epic" ]]; then
            GH_TOKEN="$GITHUB_TOKEN" gh workflow run autopilote.yml --ref "$(default_branch)" -f declencheur=chaine -f "pour=$POUR" -f "profondeur=$((PROFONDEUR+1))"
        fi
        ;;
    resume)
        board
        faites=$(git log --since='24 hours ago' --format=%s | sed -nE 's/^Autopilote : ([^ ]+) (implémentée et relue|implémentée|relue|planifiée) \(.*/- \1 (\2)/p' | sort -u)
        prs=$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --search 'Autopilote in:title' --json number,title,url --jq '.[] | "- #\(.number) \(.title) : \(.url)"')
        quota=$(python3 -c 'import json,sys; b=(json.load(open(sys.argv[1])) or [{}])[0].get("body",""); print("\n".join(l for l in b.splitlines() if l.startswith("Quota")))' "$RUNNER_TEMP/tableau.json")
        numero=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[0]["number"] if d else "")' "$RUNNER_TEMP/tableau.json")
        [[ -n "$numero" ]] || { echo "Pas de tableau de bord"; exit 0; }
        {
            echo "@${GITHUB_REPOSITORY_OWNER:-${GITHUB_REPOSITORY%%/*}} résumé des dernières 24 h"
            echo; echo "**Terminé :**"; echo "${faites:-- rien}"
            echo; echo "**PR à valider :**"; echo "${prs:-- aucune}"
            echo; echo "**File d'attente :**"; etat statut | sed 's/^/- /'; echo
            echo "${quota:-Quota Codex : inconnu}"
        } > "$RUNNER_TEMP/resume.md"
        gh issue comment "$numero" --repo "$GITHUB_REPOSITORY" --body-file "$RUNNER_TEMP/resume.md"
        ;;
    boucle)
        # Plusieurs stories dans le même run : évite un démarrage complet de la CI par story.
        debut=$(date +%s); n=0
        while :; do
            "$0" marquer && "$0" codex && "$0" publier || { echo "Boucle interrompue (erreur)"; break; }
            n=$((n + 1)); source "$state"
            echo "Story $n : ${STORY:-$EPIC} → ${RESULTAT:-?}"
            [[ ${QUOTA_ATTEINT:-false} != true && ${AUTH_KO:-false} != true ]] || break
            (( n < ${MAX_PAR_RUN:-6} && $(date +%s) - debut < ${BUDGET_RUN_MINUTES:-150} * 60 )) || break
            git pull --no-rebase -q || break
            grep -E '^export (CINQ_HEURES|SEMAINE|RESET_CINQ|RESET_SEMAINE|ALERTE_AUTH)=' "$state" > "$RUNNER_TEMP/garde" || true
            : > "$state"   # sinon le décideur relirait la story qu'on vient de finir
            DECLENCHEUR=chaine STORY='' "$0" decider > /dev/null
            cat "$RUNNER_TEMP/garde" >> "$state"; source "$state"
            [[ "$GO" == true ]] || { out go true; out raison fin-de-file; break; }
        done
        ;;
    *) echo 'Usage : autopilote.sh decider|resume|boucle|marquer|codex|sauver-auth|publier|tableau|enchainer' >&2; exit 2 ;;
esac
