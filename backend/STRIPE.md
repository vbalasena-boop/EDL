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

## ⚠️ Important : abonnements mensuels
La création auto gère le **1er paiement**. Pour un **abonnement mensuel**, la clé est
créée avec **1 mois de validité**. Le **renouvellement automatique** (prolonger la clé
chaque mois quand Stripe re-prélève) nécessite un **webhook** `invoice.paid` — c'est
l'étape suivante à ajouter.

👉 Pour démarrer **sans ce risque**, vends d'abord en **paiement unique** (ex. « Pack »
ou « 1 mois »), le temps d'ajouter le webhook de renouvellement.
