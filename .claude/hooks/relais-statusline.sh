#!/bin/bash
# Barre d'état Claude Code : affiche le quota de l'abonnement et le mémorise
# pour le hook relais-quota.sh. Les pourcentages n'existent qu'avec un
# abonnement Pro/Max, après la première réponse de la session.
exec python3 -c '
import json, os, sys, tempfile, time

try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
rl = d.get("rate_limits") or {}

def fen(nom):
    f = rl.get(nom) or {}
    p = f.get("used_percentage")
    return (round(float(p)), f.get("resets_at")) if p is not None else (None, None)

h5, r5 = fen("five_hour")
h7, r7 = fen("seven_day")
modele = (d.get("model") or {}).get("display_name", "")

if h5 is not None or h7 is not None:
    dossier = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    os.makedirs(dossier, exist_ok=True)
    etat = {"cinq_heures": h5, "reset_cinq": r5, "semaine": h7, "reset_semaine": r7, "ts": int(time.time())}
    fd, tmp = tempfile.mkstemp(dir=dossier)
    with os.fdopen(fd, "w") as f:
        json.dump(etat, f)
    os.replace(tmp, os.path.join(dossier, "relais-quota.json"))

parts = [modele] if modele else []
if h5 is not None:
    parts.append(f"5h {h5}%")
if h7 is not None:
    parts.append(f"sem. {h7}%")
print(" · ".join(parts))
'
