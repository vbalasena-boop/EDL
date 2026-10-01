<!-- relais:debut -->
# Claude ↔ Codex — mode relais économe

Deux agents (Claude Code, Codex) se relaient sur ce dépôt ; le fondateur bascule de l'un à l'autre selon le quota restant. Tout l'état vit dans le dépôt, jamais dans une conversation.

**État** : si `_bmad-output/implementation-artifacts/sprint-status.yaml` existe (BMAD), l'état = `grep -vE ': done$'` de ce fichier + la fiche de la story. Sinon, `RELAIS.md` à la racine (« À faire / En cours / Fait », une ligne par tâche avec `Agent :`, et la section « Reprise » de la tâche en cours). Lire seulement ça, puis les fichiers nécessaires par extraits. Pas d'exploration du dépôt, pas d'audit non demandé.

**Un seul agent à la fois** (règle du fondateur) : avant toute action, `git pull`, puis regarder les tâches en cours. Si l'une porte l'autre agent et que le dernier commit date de moins d'1 h (`git log -1 --format=%cr`), ne rien modifier et répondre en une ligne : « <Agent> travaille déjà : dis-lui « relais » d'abord. » Au-delà d'1 h, l'autre agent est considéré arrêté : reprendre sa tâche.
**Verrou Codex cloud** : Codex relancé par le veilleur travaille dans une PR, invisible sur la branche par défaut. Avant de reprendre une tâche arrêtée, vérifier sur GitHub : une issue ouverte au label `veilleur` contenant une mention `@codex`, ou une PR ouverte de Codex, signifie que **Codex a la main** → ne rien modifier et répondre « Codex a repris la suite : valide sa PR d'abord. » Le verrou tombe quand la PR est fusionnée. Sans accès GitHub pour vérifier, demander au fondateur.

**Zones** (préférence, pas verrou) : Claude = back-end, base de données, sécurité, paiements ; Codex = pages, composants, design. Rien de prêt dans sa zone → prendre n'importe quelle tâche prête.

**Commandes du fondateur** :
- « prends la suite » → tâche en cours dont l'agent est arrêté (relais ou > 1 h), sinon la prochaine à faire.
- « relais » → point de reprise, `Agent : relais`, push, réponse d'une ligne.
- « statut » → une ligne par tâche ouverte.
- Demande nouvelle → petite tâche (≤ 1 h, critères vérifiables, `Agent :`) ajoutée à l'état, puis traitée.

**Points de reprise** : après chaque étape utile, mettre à jour « Reprise » (fait / reste / prochaine commande, 3 lignes max), committer, pousser.

**Fini** = critères vérifiés + tests/lint/build du projet OK (ciblés pendant le travail, complets une fois à la fin).

**Économie** : réponses en français, 5 lignes max, sans récapitulatif.
<!-- relais:fin -->
