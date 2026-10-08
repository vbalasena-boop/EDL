#!/usr/bin/env python3
"""État BMAD, sans dépendance YAML."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import time

STATUTS = ('backlog', 'ready-for-dev', 'in-progress', 'review', 'done')
MODELES = {'simple': 'gpt-5.5', 'moyen': 'gpt-6-sol', 'complexe': 'gpt-6-astra'}


def chemin():
    return Path(os.environ.get('RELAIS_STATUT', '_bmad-output/implementation-artifacts/sprint-status.yaml'))


def lignes():
    return chemin().read_bytes().decode().splitlines(keepends=True)


def entrees():
    actif = False
    for index, ligne in enumerate(lignes()):
        if re.match(r'^development_status:\s*(?:#.*)?$', ligne):
            actif = True
            continue
        if actif and re.match(r'^\S', ligne) and not ligne.startswith('#'):
            actif = False
        if actif:
            match = re.match(r'^  ([\w-]+):([ \t]*)([\w-]+)([^\r\n]*)(\r?\n)?$', ligne)
            if match:
                yield index, match


def etats():
    return {m[1]: m[3] for _, m in entrees()}


def fiche(cle):
    dossier = chemin().parent
    exact = dossier / ('spec-' + cle + '.md')
    if exact.exists():
        return exact
    candidats = [p for p in dossier.glob('spec-*.md')
                  if p.stem[5:].startswith(cle) or cle.startswith(p.stem[5:])]
    if len(candidats) != 1:
        raise ValueError('fiche absente ou ambiguë : ' + cle)
    return candidats[0]


def champ(ligne, nom):
    return re.match(r'^([ \t]*(?:-[ \t]*)?\**[ \t]*' + nom + r'[ \t]*\**[ \t]*:[ \t]*\**[ \t]*)(.*?)(\r?\n)?$', ligne, re.I)


def meta(cle):
    p = fiche(cle)
    resultat = dict(agent='codex', niveau='complexe', priorite='normale', statut=etats().get(cle, ''), fiche=str(p))
    texte = p.read_text()
    for ligne in texte.splitlines()[:25]:
        for nom in ('agent', 'niveau', 'priorité', 'priorite'):
            match = champ(ligne, nom)
            if match:
                resultat[nom.replace('é', 'e')] = match[2].strip(' *').lower()
    resultat['modele'] = MODELES.get(resultat['niveau'], MODELES['complexe'])
    # Après un échec de l'autopilote, on monte au modèle le plus puissant avant de rendre la story à Claude.
    resultat['echecs'] = str(len(re.findall(r'^- Autopilote : échec \d+', texte, re.M)))
    if resultat['echecs'] != '0':
        resultat['modele'] = MODELES['complexe']
    return resultat


def stories():
    return {k: v for k, v in etats().items() if not k.startswith('epic-') and not k.endswith('-retrospective')}


def dependances_ouvertes(texte, statuts):
    """Clés complètes citées dans la ligne « Dépendances » de la fiche et pas encore done."""
    for ligne in texte.splitlines()[:25]:
        match = champ(ligne, 'd[ée]pendances')
        if match:
            return [k for k, v in statuts.items() if k in match[2] and v != 'done']
    return []


def prochaine(pour='codex', seuil=60, max_echecs=2):
    candidats = []
    statuts = etats()
    for cle, statut in stories().items():
        if statut not in ('review', 'in-progress', 'ready-for-dev'):
            continue
        try:
            m = meta(cle)
        except ValueError:
            # Une fiche absente/ambiguë ne peut pas être confiée à un agent.
            continue
        if pour == 'codex' and m['agent'] == 'claude':
            continue
        # En review chez Claude = PR à valider par Claude : l'autopilote n'y touche plus.
        if statut == 'review' and m['agent'] == 'claude':
            continue
        # Trop d'échecs de l'autopilote : la story attend Claude.
        if max_echecs and len(re.findall(r'^- Autopilote : échec \d+', Path(m['fiche']).read_text(encoding='utf-8'), re.M)) >= max_echecs:
            continue
        # Une story dont un prérequis n'est pas terminé attend (sinon elle part sans son socle).
        if statut == 'ready-for-dev' and dependances_ouvertes(Path(m['fiche']).read_text(encoding='utf-8'), statuts):
            continue
        priorite = {'review': 0, 'in-progress': 1, 'ready-for-dev': 2}[statut]
        if statut == 'in-progress' and m['agent'] != 'relais':
            p = Path(m['fiche']).resolve()
            run = subprocess.run(['git', 'log', '-1', '--format=%ct', '--', p.name], cwd=p.parent,
                                 capture_output=True, text=True)
            date = run.stdout.strip()
            if date and time.time() - int(date) <= seuil * 60:
                continue
        rang = {'haute': 0, 'normale': 1, 'basse': 2}.get(m.get('priorite', 'normale'), 1)
        candidats.append((priorite, rang, len(candidats), cle))
    return min(candidats)[3] if candidats else ''


def epic():
    for cle, statut in etats().items():
        if cle.startswith('epic-') and not cle.endswith('-retrospective') and statut == 'in-progress':
            nom = cle[5:]
            prefixe = (nom.split('-')[0] if nom.split('-')[0].isdigit() else nom) + '-'
            if not any(k.startswith(prefixe) and v in ('review', 'in-progress', 'ready-for-dev') for k, v in stories().items()):
                return cle
    return ''


def passer(cle, statut, agent=None):
    contenu = lignes()
    for index, m in entrees():
        if m[1] == cle:
            contenu[index] = '  ' + cle + ':' + m[2] + statut + m[4] + (m[5] or '')
            break
    else:
        raise ValueError('story inconnue : ' + cle)
    p = fiche(cle) if agent else None
    chemin().write_bytes(''.join(contenu).encode())
    if p:
        texte = p.read_bytes().decode().splitlines(keepends=True)
        for index, ligne in enumerate(texte[:25]):
            m = champ(ligne, 'agent')
            if m:
                texte[index] = m[1] + agent + (m[3] or '')
                break
        else:
            index = next((i + 1 for i, l in enumerate(texte) if l.startswith('#')), 0)
            texte.insert(index, '\n**Agent :** ' + agent + '\n')
        p.write_bytes(''.join(texte).encode())


def quota(home):
    resultat = dict(cinq_heures='', semaine='', reset_cinq='', reset_semaine='')
    fichiers = list((Path(home) / 'sessions').rglob('rollout-*.jsonl'))
    if not fichiers:
        return resultat
    fichier = max(fichiers, key=lambda p: p.stat().st_mtime_ns)
    for ligne in reversed(fichier.read_text().splitlines()):
        try:
            event = json.loads(ligne)
        except ValueError:
            continue
        payload = event.get('payload', {})
        if event.get('type') != 'event_msg' or payload.get('type') != 'token_count':
            continue
        limites = payload.get('rate_limits') or {}
        for nom, pct, reset in [('primary', 'cinq_heures', 'reset_cinq'), ('secondary', 'semaine', 'reset_semaine')]:
            valeur = limites.get(nom) or {}
            resultat[pct] = valeur.get('used_percent', '')
            resultat[reset] = valeur.get('resets_at', '')
            if resultat[reset] == '' and 'resets_in_seconds' in valeur:
                try:
                    base = datetime.datetime.fromisoformat(event['timestamp'].replace('Z', '+00:00')).timestamp()
                except (KeyError, ValueError):
                    base = time.time()
                resultat[reset] = int(base + valeur['resets_in_seconds'])
        break
    return resultat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='cmd', required=True)
    for nom in ('statut', 'epic-a-planifier'):
        sub.add_parser(nom)
    p = sub.add_parser('prochaine')
    p.add_argument('--pour', choices=('codex', 'tous'), default='codex')
    p.add_argument('--seuil', type=int, default=60)
    p.add_argument('--max-echecs', type=int, default=2)
    for nom in ('fiche', 'meta', 'passer'):
        p = sub.add_parser(nom)
        p.add_argument('cle')
        if nom == 'passer':
            p.add_argument('statut', choices=STATUTS)
            p.add_argument('--agent')
    sub.add_parser('quota-codex').add_argument('home')
    args = parser.parse_args()
    try:
        if args.cmd == 'statut':
            for cle, statut in stories().items():
                if statut not in ('done', 'backlog', 'optional'):
                    try:
                        agent = meta(cle)['agent']
                    except ValueError:
                        agent = 'codex'
                    print(f"{cle} : {statut} · {agent}")
        elif args.cmd == 'prochaine':
            valeur = prochaine(args.pour, args.seuil, args.max_echecs)
            if valeur:
                print(valeur)
        elif args.cmd == 'epic-a-planifier':
            valeur = epic()
            if valeur:
                print(valeur)
        elif args.cmd == 'fiche':
            print(fiche(args.cle))
        elif args.cmd == 'meta':
            m = meta(args.cle)
            for k in ('agent', 'niveau', 'priorite', 'echecs', 'modele', 'statut', 'fiche'):
                print(f'{k}={m[k]}')
        elif args.cmd == 'passer':
            passer(args.cle, args.statut, args.agent)
        else:
            for k, v in quota(args.home).items():
                print(f'{k}={v}')
    except (ValueError, OSError) as exc:
        parser.exit(1, str(exc) + '\n')


if __name__ == '__main__':
    main()
