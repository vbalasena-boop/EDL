# Immoscan — Créer les clés d'accès à la main (Cloudflare KV)

Tant que le paiement Stripe n'est pas automatisé, tu crées toi-même la clé d'accès
de chaque client dans le stockage **LICENSES**.

## Où créer une clé
1. **dash.cloudflare.com** → **Workers & Pages** → **KV** → ouvre **`LICENSES`**.
2. **Add entry** :
   - **Key** = la clé d'accès du client (ex. `IMS-XPAE-C568`)
   - **Value** = un des JSON ci-dessous (selon la formule payée)
3. **Save**. Envoie la clé au client → il la colle dans ⚙️ Réglages de l'app.

> `limit` = nombre d'analyses autorisées · `expires` = date de fin `"AAAA-MM-JJ"` ou `null` (jamais).
> Rappel : 1 état des lieux complet ≈ 10 à 15 analyses.

## JSON par formule (copier-coller)

**Essai gratuit (20 analyses, sans fin)**
```json
{"plan":"essai","limit":20,"used":0,"expires":null}
```

**Solo — 19 €/mois (400 analyses)**
```json
{"plan":"solo","limit":400,"used":0,"expires":"2026-09-29"}
```

**Pro — 39 €/mois (1200 analyses)**
```json
{"plan":"pro","limit":1200,"used":0,"expires":"2026-09-29"}
```

**Illimité — 79 €/mois (affiche « ∞ » dans l'app)**
```json
{"plan":"illimite","limit":9999999,"used":0,"expires":"2026-09-29"}
```

**Pack 9 € (200 analyses, valables ~3 mois)**
```json
{"plan":"pack","limit":200,"used":0,"expires":"2026-11-29"}
```

**Ta clé admin perso (illimitée, sans fin)**
```json
{"plan":"admin","limit":9999999,"used":0,"expires":null}
```

## Renouvellement mensuel (à la main pour l'instant)
Quand un client paie son mois suivant :
1. Ouvre son entrée dans `LICENSES`.
2. Mets **`"used":0`** (recompteur à zéro).
3. Mets **`"expires"`** à la nouvelle date de fin (ex. mois suivant).
4. Save.

## Quand il ne paie plus
- Soit tu laisses **`expires`** passer (la clé se bloque toute seule à la date).
- Soit tu **supprimes l'entrée** (Delete) → accès coupé immédiatement.

## Verrou multi-appareils (anti-partage)
Chaque clé n'accepte que **2 appareils** par défaut. Un 3ᵉ appareil est refusé
(« Clé déjà utilisée sur 2 appareils… »).

- **Changer la limite** : ajoute `"maxDevices"` dans le JSON du client
  (ex. `"maxDevices":1` pour un seul appareil, `"maxDevices":3` pour trois, `0` = illimité).
  ```json
  {"plan":"solo","limit":400,"used":0,"expires":"2026-09-29","maxDevices":2}
  ```
- **Réinitialiser les appareils** (client qui change de téléphone) : ouvre son entrée KV
  et remets **`"devices":[]`** (ou supprime la ligne `devices`), puis Save.
- Ta **clé admin** (`"plan":"admin"`) n'est jamais limitée en appareils.

## Bon à savoir
- La clé peut être n'importe quelle chaîne ; le préfixe `IMS-` est juste pour t'y retrouver.
- Le champ `devices` se remplit tout seul (les identifiants des appareils utilisés) — tu n'as pas à le créer.
