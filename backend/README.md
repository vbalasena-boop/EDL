# EDL IA — Déploiement du serveur (Cloudflare Worker)

Le serveur cache ta clé Gemini et vérifie la **clé d'accès** de chaque client.
Tout se fait depuis le **tableau de bord Cloudflare** (gratuit), sans terminal.

---

## Étape 1 — Créer un compte Cloudflare (gratuit)
1. Va sur **dash.cloudflare.com** → **Sign up**.
2. Confirme ton email.

## Étape 2 — Créer le Worker (le serveur)
1. Menu de gauche → **Workers & Pages** → **Create** → **Create Worker**.
2. Donne-lui un nom, ex : **`edl-ia-api`** → **Deploy** (il déploie un exemple).
3. Clique **Edit code** → **efface tout** → **colle le contenu de `worker.js`** → **Deploy**.
4. Note l'adresse du Worker affichée, ex :
   **`https://edl-ia-api.TON-SOUS-DOMAINE.workers.dev`** → tu en auras besoin.

## Étape 3 — Créer le stockage des clés d'accès (KV)
1. **Workers & Pages** → **KV** → **Create a namespace** → nomme-le **`LICENSES`** → Create.

## Étape 4 — Brancher le stockage au Worker
1. Ouvre ton Worker **`edl-ia-api`** → **Settings** → **Bindings** (ou *Variables*).
2. **Add binding** → type **KV namespace** :
   - **Variable name** : `LICENSES` (exactement)
   - **KV namespace** : choisis `LICENSES`
3. Enregistre / Deploy.

## Étape 5 — Mettre ta clé Gemini en secret
1. Même écran **Settings** → **Variables and Secrets** → **Add**.
2. **Type : Secret** — **Name** : `GEMINI_KEY` — **Value** : ta clé Google Gemini.
3. (Optionnel) Ajoute une variable **`ALLOW_ORIGIN`** = l'adresse de ton app
   (ex : `https://vbalasena-boop.github.io`). Laisse vide/`*` pendant les tests.
4. Enregistre / Deploy.

## Étape 6 — Créer une clé d'accès de test
1. **Workers & Pages** → **KV** → ouvre **`LICENSES`** → **Add entry** :
   - **Key** (la clé d'accès du client) : ex `EDL-TEST-2026`
   - **Value** (colle ce JSON) :
     ```json
     {"plan":"test","limit":50,"used":0,"expires":null}
     ```
   - `limit` = nombre d'analyses autorisées · `expires` = date `"2027-01-01"` ou `null`.
2. Save.

## Étape 7 — Tester
- Dans l'app **pro** (`pro.html`), colle l'adresse du Worker + la clé `EDL-TEST-2026`.
- Fais une analyse : si ça marche, le serveur relaie à Gemini **sans jamais exposer ta clé**. ✅

---

## Comment vendre ensuite
- Le client **paie** (lien Stripe) → tu crées une **nouvelle entrée KV** avec une clé d'accès unique (ex `EDL-9F3K-2026`) et son quota → tu la lui envoies.
- Plus tard, on **automatise** : un webhook Stripe crée la clé automatiquement après paiement (étape suivante du projet).

## Suivi des usages
Chaque analyse incrémente `used` dans l'entrée KV du client. Quand `used`
atteint `limit`, le serveur refuse (quota atteint) jusqu'au renouvellement.
