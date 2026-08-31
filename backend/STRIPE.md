# Immoscan — Paiement automatique (Stripe)

Après paiement, la clé d'accès est **créée automatiquement** et affichée au client
sur la page **`merci.html`**. Aucun webhook à configurer.

## Comment ça marche
1. Le client clique sur un bouton de `vente.html` → il paie sur **Stripe** (Payment Link).
2. Stripe le redirige vers **`merci.html?session_id=cs_...`**.
3. `merci.html` appelle le serveur (`GET /checkout?session_id=...`).
4. Le serveur vérifie le paiement auprès de Stripe, **crée la clé** dans KV, et la renvoie.
5. Le client copie sa clé et la colle dans ⚙️ Réglages de l'app.

---

## Étape 1 — Récupérer ta clé secrète Stripe
- **dashboard.stripe.com** → **Développeurs** → **Clés API** → copie la **clé secrète**
  (`sk_test_...` pour tester, `sk_live_...` en réel).

## Étape 2 — L'ajouter au Worker Cloudflare
- Worker `edl-ia-api` → **Settings** → **Variables and Secrets** → **Add** :
  - Type **Secret** — Name **`STRIPE_KEY`** — Value : ta clé secrète Stripe.
- **Deploy**.
- (Puis re-colle le `worker.js` à jour et Deploy, si ce n'est pas déjà fait.)

## Étape 3 — Créer tes produits + prix
Dans Stripe → **Catalogue de produits**, crée les prix (montants EXACTS, sinon adapte
`planFromAmount` dans `worker.js`) :

| Produit | Prix | Type |
|---|---|---|
| Immoscan Solo | **19,00 €** | mensuel (ou unique) |
| Immoscan Pro | **39,00 €** | mensuel (ou unique) |
| Immoscan Illimité | **79,00 €** | mensuel (ou unique) |
| Pack 200 analyses | **9,00 €** | paiement unique |

## Étape 4 — Créer les Payment Links (avec redirection)
Pour **chaque** prix → **Payment Links** → **Create link** :
1. Sélectionne le prix.
2. **Après le paiement** → **Rediriger vers une page** → colle EXACTEMENT :
   ```
   https://vbalasena-boop.github.io/EDL/merci.html?session_id={CHECKOUT_SESSION_ID}
   ```
   ⚠️ Garde bien `{CHECKOUT_SESSION_ID}` tel quel (Stripe le remplace automatiquement).
3. Crée le lien → copie l'URL `https://buy.stripe.com/...`.

## Étape 5 — Brancher les liens dans la page de vente
Dans `vente.html`, en bas, remplis :
```js
const STRIPE_LINKS = {
  solo: "https://buy.stripe.com/xxxxSOLO",
  pro: "https://buy.stripe.com/xxxxPRO",
  illimite: "https://buy.stripe.com/xxxxILLIMITE"
};
```

## Étape 6 — Tester (mode test)
- Utilise la **clé secrète de TEST** (`sk_test_...`) dans `STRIPE_KEY` et des **Payment Links de test**.
- Carte de test : **4242 4242 4242 4242**, date future, CVC quelconque.
- Paie → tu dois arriver sur `merci.html` avec une clé affichée. ✅
- Passe ensuite en **mode réel** (clé `sk_live_...` + liens live).

---

## Abonnements mensuels — renouvellement automatique (webhook)
- **1er paiement** → clé créée par `/checkout` (page Merci), valable 1 mois.
- **Renouvellements** (mois suivants) → gérés par le **webhook** : la clé se **prolonge d'un
  mois** et son **quota repart à zéro** automatiquement.

### Configurer le webhook (une fois)
1. Stripe → **Développeurs → Webhooks → Ajouter un point de terminaison**.
2. **URL du point de terminaison** :
   ```
   https://edl-ia-api.monkey-pro-instant-events.workers.dev/webhook
   ```
3. **Événements à écouter** : coche **`invoice.paid`** (tu peux aussi ajouter
   `invoice.payment_succeeded`).
4. Crée → ouvre le point de terminaison → **« Signing secret »** → **Révéler** → copie
   la valeur **`whsec_...`**.
5. Cloudflare → `edl-ia-api` → Settings → Variables → **Add** :
   - Type **Secret** — Name **`STRIPE_WEBHOOK_SECRET`** — Value : le `whsec_...`.
   - **Deploy**.

> ⚠️ Le webhook doit être créé dans le **même mode** (test/réel) que tes Payment Links,
> et son secret `whsec_...` correspond à ce mode.

### Résiliation
Quand un client résilie, Stripe arrête les prélèvements → plus de `invoice.paid` → la clé
n'est plus prolongée et **expire à la fin du mois payé**. Rien à faire de ton côté.
