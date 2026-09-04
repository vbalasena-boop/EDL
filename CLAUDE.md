# Immoscan — contexte projet (lu automatiquement par Claude Code)

## En une phrase
**Immoscan** : PWA française qui rédige des **états des lieux (EDL)** à partir de photos via
Google Gemini, à coller dans n'importe quel logiciel d'EDL (copier-coller), avec un
**comparateur entrée/sortie**, une **estimation de vétusté** et un **export PDF**.
Cible : gestion locative (gestionnaires, administrateurs de biens, agences). Vendu en SaaS via Stripe.

- Propriétaire : Vobinson BALASENA (EI) — infos légales complètes dans `legal.html` / `cgv.html`.
- Langue : **tout en français** (UI, commits, réponses). Tutoiement dans l'app.
- Site : https://vbalasena-boop.github.io/EDL/ (GitHub Pages)

## Fichiers (tout est statique, aucun build)
| Fichier | Rôle |
|---|---|
| `pro.html` | **L'app** (scan photos → descriptif). `APP_VERSION` à bumper à chaque changement de l'app. |
| `comparateur.html` | Page séparée : import ancien + nouveau EDL (photos/PDF) → comparaison IA, calculateur vétusté, export PDF (impression navigateur). |
| `vente.html` | Page de vente (hero + démo animée, stats, avant/après, **bandeau premium comparateur**, étapes, témoignage, tarifs, FAQ). Contient `STRIPE_LINKS` (4 Payment Links live). |
| `merci.html` | Retour Stripe : appelle `GET /checkout?session_id=` et affiche la clé créée. |
| `legal.html` / `cgv.html` | Mentions légales + RGPD / Conditions Générales de Vente (même style). |
| `sw.js` | Service worker **stale-while-revalidate** (cache `edl-cache-v1`). |
| `manifest.webmanifest` | PWA (start_url `pro.html`, raccourcis « Scanner » et « Comparateur »). |
| `icon-*.png` | Icônes (générées via PIL). |
| `backend/worker.js` | **Cloudflare Worker** : proxy Gemini + licences KV + Stripe (`/checkout`, `/webhook`) + `/me`. Déployé à la main via le dashboard Cloudflare (copier-coller). |
| `backend/STRIPE.md`, `backend/GUIDE-CLES.md`, `backend/README.md` | Guides de déploiement / recettes de clés. |
| `index.html`, `GUIDE-EDL-IA-MULTI-PHOTOS.md` | **Legacy** (ancien « EDL IA », raccourci iOS). Ne pas y travailler. |

## Architecture
- Client → `POST https://edl-ia-api.monkey-pro-instant-events.workers.dev` avec en-têtes `X-License`, `X-Device`
  et body `{model, contents, generationConfig}` transmis **tel quel** à Gemini (images `image/jpeg` et PDF `application/pdf` en `inline_data`).
- Modèles : `gemini-flash-lite-latest` (« Rapide », défaut) ; `gemini-flash-latest` (« Meilleure qualité », compteurs, comparateur).
  ⚠️ `gemini-2.5-flash` a été supprimé par Google → migration dans `currentModel()`. Toujours utiliser les alias `-latest`.
- Licences KV `LICENSES` : `{plan, limit, used, expires, maxDevices, devices[]}` ; plan `admin` = illimité.
- Sécurité Worker : verrou d'origine (`ALLOW_ORIGIN`), **20 req/min par clé**, verrou multi-appareils (2, 3 pour Illimité), CORS `Content-Type, X-License, X-Device`.
- Stripe : Payment Links → `merci.html?session_id={CHECKOUT_SESSION_ID}` → `/checkout` crée la clé `IMS-XXXX-XXXX` ; webhook `invoice.paid` (`subscription_cycle`) prolonge d'1 mois + remet `used=0`. `planFromAmount` : 1900→solo/400, 3900→pro/1200, 7900→illimite, 900→pack/200 (3 mois).
- Stockage client : `localStorage` (clés `edlpro_*` : license, element, room, last, report, model, camface, device…) ; IndexedDB `edlpro_db` v2 stores `jobs` (file hors-ligne) et `archives` (rapports archivés). **Rien n'est stocké côté serveur** (choix RGPD, écrit dans CGV/legal).
- Même origine ⇒ `comparateur.html` partage la clé d'accès de l'app via `localStorage`.

## Règles produit (ne pas régresser)
- Sortie IA **sans émoji ni symbole décoratif**, pas d'intro/conclusion, français. `cleanText()` strippe les émojis.
- Élément seul : commencer par **matière + état**, sans répéter le nom de l'élément ; **jamais** de sous-noms de murs (« mur principal/gauche… »).
- Critères d'état fixes : Très bon / Bon / État d'usage / Mauvais (définitions objectives dans `buildPrompt`).
- Pas de mention de **Nockee** (retirée : fonctionne avec tous les logiciels).
- Scan : tout doit tenir **sans défiler** jusqu'à la barre flottante (dock : Photo / Analyser / Copier / Effacer). Effacer = **sans confirmation**.
- Caméra intégrée (rafale, arrière par défaut), flux gardé « au chaud » 45 s (moins de prompts iOS). L'overlay `#cam` doit rester **avant** le `<script>`.
- Rapport : **Vider archive automatiquement** avant d'effacer. Exporter = Web Share (fichier → texte → téléchargement).
- Vétusté : grille **indicative** (aucune grille officielle en France), toujours éditable, disclaimers obligatoires.
- Décision actée : la bascule Entrée/Sortie *dans l'app* a été **retirée** au profit de la page comparateur séparée.

## Déploiement & cache (piège n°1)
- GitHub Pages déploie **cette branche** `claude/photo-analysis-property-reports-shwqhf` (seule branche du dépôt, aussi branche par défaut ⇒ pas de PR possible). Push = mise en ligne en ~1 min.
- Le SW sert d'abord le cache : l'utilisateur voit les nouveautés **au 2ᵉ chargement** ou via ⚙️ → « ↻ Forcer la mise à jour ». Quand l'utilisateur « ne voit pas » un changement, c'est presque toujours ça.
- Bumper `APP_VERSION` dans `pro.html` à chaque modification de l'app.

## Développer / tester ici (sandbox)
- Aucun accès sortant : **impossible** d'atteindre le Worker, Stripe, Gemini ou github.io depuis le sandbox → les tests live sont faits par l'utilisateur.
- Prévisualisation : `python3 -m http.server 8099` à la racine, puis Playwright : `require('/opt/node22/lib/node_modules/playwright')` (Chromium headless, `deviceScaleFactor:2`, viewports 390 et 1280). Stubber `fetch` pour simuler le backend. Ignorer l'erreur `ERR_CONNECTION_RESET` des Google Fonts.
- Vérifier le déploiement : GitHub MCP `actions_list` (workflow « pages build and deployment »).
- Éditions : remplacements exacts avec vérification (python) ; screenshots avant/après pour tout changement d'UI ; tester mobile **et** desktop.
- Commits en français, messages détaillés, **jamais** de nom de modèle dans les commits/PR.

## Historique des versions app (repères)
5.3 compteurs/miroir/cam au chaud · 6.0 lien comparateur · 6.1 bouton ⚖️ dans l'en-tête · 6.2 export/archives des rapports + CGV.

## Feuille de route (par priorité, validée avec le propriétaire)
1. **Nom de domaine** (immoscan.fr) → à brancher sur GitHub Pages (CNAME) puis mettre à jour `ALLOW_ORIGIN` du Worker et les redirections Stripe.
2. Faire relire les **CGV** par un juriste ; procédure « retrouver ma clé ».
3. Mesure (analytics respectueux) et **5 gestionnaires testeurs**.
4. Ensuite seulement : générateur d'annonces (cible agents), etc.
