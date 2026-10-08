#!/usr/bin/env python3
"""Rendu du tableau de bord (aucun accès réseau ni secret)."""
import datetime
import json
import os
from pathlib import Path
import re
import sys
import time
from zoneinfo import ZoneInfo


def rendre(dossier):
    p = Path(dossier)
    env = os.environ
    now = int(time.time())
    items = json.loads((p / 'tableau.json').read_text())
    ancien = items[0]['body'] if items else ''

    def marque(nom):
        m = re.search(r'<!--\s*' + nom + r'=(\d+)\s*-->', ancien)
        return int(m[1]) if m else 0

    def date(epoch):
        try:
            return datetime.datetime.fromtimestamp(float(epoch), ZoneInfo('Europe/Paris')).strftime('%d/%m/%Y %H:%M %Z')
        except (ValueError, TypeError, OverflowError):
            return 'inconnu'

    reprise = marque('reprise_codex_apres')
    tous = marque('pour_tous_jusqua')
    quota = env.get('QUOTA_ATTEINT') == 'true'
    for pct, reset in [('CINQ_HEURES', 'RESET_CINQ'), ('SEMAINE', 'RESET_SEMAINE')]:
        valeur = env.get(pct, '')
        if (valeur and float(valeur) >= 95) or (quota and not valeur):
            reprise = max(reprise, int(float(env.get(reset) or now + 1800)))
    if quota and reprise <= now:
        # Pourcentages inconnus : on attend le reset 5 h, pas celui de la semaine (trop pessimiste).
        reprise = max(now + 1800, int(float(env.get('RESET_CINQ') or 0)))
    if env.get('DECLENCHEUR') in ('limite-claude', 'relais'):
        tous = now + 6 * 3600
    url = f"https://github.com/{env['GITHUB_REPOSITORY']}/actions/runs/{env['GITHUB_RUN_ID']}"
    texte = f"Dernier run : {date(now)} · {env.get('DECLENCHEUR')} · {env.get('STORY') or env.get('EPIC', '')} · {env.get('MODE', '')} · {env.get('RESULTAT') or env.get('RAISON', 'interrompu')}\n{url}\n\n"
    texte += f"Quota Codex 5 h : {env.get('CINQ_HEURES') or '?'} % (reset {date(env.get('RESET_CINQ'))})\n"
    texte += f"Quota semaine : {env.get('SEMAINE') or '?'} % (reset {date(env.get('RESET_SEMAINE'))})\n\nFile d'attente :\n```text\n{(p / 'file.txt').read_text()}```\n"
    if env.get('ALERTE_AUTH') or env.get('AUTH_KO') == 'true':
        texte += f"\nAlerte : {env.get('ALERTE_AUTH', '')} auth_ko={env.get('AUTH_KO', 'false')}. Sur le Mac : `scripts/relais/connexion-codex-ci.sh`. Vérifier aussi le secret RELAIS_PAT.\n"
    texte += f'\n<!-- reprise_codex_apres={reprise} -->\n<!-- pour_tous_jusqua={tous} -->\n'
    (p / 'tableau.md').write_text(texte)
    (p / 'issue-number').write_text(str(items[0]['number']) if items else '')


if __name__ == '__main__':
    rendre(sys.argv[1])
