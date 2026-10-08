#!/bin/bash
# UserPromptSubmit : ajoute une ligne au contexte de Claude quand son quota
# devient élevé (≥ 70 % sur 5 h ou ≥ 80 % sur la semaine). Rien sinon, pour
# ne pas dépenser de tokens. Source : relais-quota.json écrit par la barre d'état.
exec python3 -c '
import json, os, time

dossier = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
try:
    q = json.load(open(os.path.join(dossier, "relais-quota.json")))
except Exception:
    raise SystemExit(0)

maintenant = time.time()
if maintenant - q.get("ts", 0) > 6 * 3600:
    raise SystemExit(0)

def valeur(cle, reset):
    pct, r = q.get(cle), q.get(reset)
    if pct is None or (r and float(r) < maintenant):
        return None, None
    return pct, (time.strftime("%H:%M", time.localtime(float(r))) if r else "?")

h5, r5 = valeur("cinq_heures", "reset_cinq")
h7, r7 = valeur("semaine", "reset_semaine")
if not ((h5 or 0) >= 70 or (h7 or 0) >= 80):
    raise SystemExit(0)

mode = "relais (≥ 90 %)" if (h5 or 0) >= 90 or (h7 or 0) >= 90 else "économe"
detail = []
if h5 is not None:
    detail.append(f"5 h {h5} % (reset {r5})")
if h7 is not None:
    detail.append(f"semaine {h7} % (reset {r7})")
txt = ", ".join(detail)
print(f"Quota Claude : {txt} → mode {mode} (voir CLAUDE.md, « Quota Claude »).")
'
