<!-- relais:debut -->
# Relais Claude ↔ Codex (règles communes)

Deux agents se relaient sur ce dépôt : **Claude** planifie, vérifie et utilise les outils de production ; **Codex** code, dans une session Claude (`codex exec`) ou via l'autopilote GitHub (`.github/workflows/autopilote.yml`). Tout l'état vit dans le dépôt, jamais dans une conversation.

**État** : `python3 scripts/relais/etat.py statut` (stories ouvertes), `etat.py meta <clé>` (agent, niveau, modèle, fiche), `etat.py passer <clé> <statut> [--agent X]` pour écrire. Lire ensuite la fiche, puis les fichiers utiles par extraits. Pas d'exploration ni d'audit non demandés.

**Fiche** `_bmad-output/implementation-artifacts/spec-<clé>.md` : en tête `**Agent :** codex|claude`, `**Niveau :** simple|moyen|complexe` et `**Priorité :** haute|normale|basse` (défaut normale), puis objectif, critères vérifiables, fichiers, section « Reprise » (fait / reste / prochaine commande, 3 lignes). Statuts : `ready-for-dev` → `in-progress` → `review` → `done`.

**Un agent par story** : une story `in-progress` appartient à l'agent noté dans sa fiche (`claude`, `codex`, `autopilote`). N'y pas toucher tant que sa fiche a changé il y a moins d'1 h (2 h pour `autopilote`) ; au-delà elle est arrêtée : la reprendre. Les autres stories restent libres. Une story confiée explicitement (par Claude ou par l'autopilote) appartient à l'agent qui la reçoit, même si une autre story est en cours.

**Autopilote** (toutes les 2 h, ou lancé par Claude ou par le hook de limite Claude) : prochaine story → Codex code puis se relit dans le même run → `scripts/relais/verifier.sh` (tests, lint, types). OK → push sur la branche par défaut et story suivante. Échec, ou fichier dans `CHEMINS_SENSIBLES` (`.relais/config`) → PR brouillon. Après un échec, nouvel essai avec le modèle le plus puissant ; deux échecs → `Agent : claude`. Résumé quotidien à 18 h 47 sur le tableau de bord. Tableau de bord : issue « 🛰️ Relais — tableau de bord ».

**Commandes du fondateur** :
- « prends la suite » → Claude : autopilote pour les stories Codex, et prend lui-même les stories `claude` ; Codex : `etat.py prochaine`.
- « relais » → point de reprise, push, autopilote pour toutes les stories (`pour=tous`), réponse d'une ligne.
- « statut » → `etat.py statut` + lien du tableau de bord.
- Demande nouvelle → petite fiche (≤ 1 h, critères vérifiables, Agent, Niveau) en `ready-for-dev`, puis aiguillage.

**Points de reprise** : après chaque étape utile, mettre à jour « Reprise », committer, `git pull --no-rebase`, pousser sur la branche par défaut.

**Fini** = critères cochés + `scripts/relais/verifier.sh` OK (ciblé pendant le travail, complet à la fin).

**Économie** : réponses en français, 5 lignes max, sans récapitulatif.
<!-- relais:fin -->
