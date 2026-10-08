#!/usr/bin/env bash
set -euo pipefail
repo=${1:-vbalasena-boop/asso-manager}
# Une connexion dédiée par dépôt : le jeton tourne et ne doit jamais être partagé.
export CODEX_HOME="$HOME/.codex-ci-${repo##*/}"
mkdir -p "$CODEX_HOME"
umask 077
case ${2:---device-auth} in
    --browser) codex login ;;
    --device-auth) codex login --device-auth ;;
    *) echo "Usage : $0 [dépôt] [--device-auth|--browser]" >&2; exit 2 ;;
esac
chmod 600 "$CODEX_HOME/auth.json"
if gh auth status >/dev/null 2>&1; then
    base64 < "$CODEX_HOME/auth.json" | gh secret set CODEX_AUTH_CI --repo "$repo"
else
    base64 < "$CODEX_HOME/auth.json" | pbcopy
    echo "Valeur copiée dans le presse-papiers : https://github.com/$repo/settings/secrets/actions"
fi
if ! gh secret list --repo "$repo" --json name --jq '.[].name' 2>/dev/null | grep -qx RELAIS_PAT; then
    echo 'Créer RELAIS_PAT : PAT fin, dépôt ciblé, permission Secrets : Read and write.'
    echo 'https://github.com/settings/personal-access-tokens/new'
fi
printf '%s\n' 'Cette connexion est dédiée à la CI.' 'Ne plus utiliser ce dossier ailleurs : le refresh token est à usage unique.' 'Pour renouveler le secret, relancer ce script avec une nouvelle connexion dédiée.'
