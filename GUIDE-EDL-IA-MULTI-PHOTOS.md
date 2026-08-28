# EDL IA — Analyse multi‑photos pour état des lieux

Guide pour faire évoluer le raccourci iOS **EDL IA** afin qu'il prenne **plusieurs
photos**, les envoie **toutes dans une seule requête** à l'API Gemini, et renvoie
**un seul descriptif** d'état des lieux prêt à coller (dans Nokee, Notes, etc.).

---

## 1. Le principe

L'API Gemini accepte plusieurs images dans une même requête. Dans le corps JSON,
le tableau `parts` contient **1 texte + N images** :

```
"parts": [
  { "text": "…le prompt…" },
  { "inline_data": { "mime_type": "image/jpeg", "data": "…base64 photo 1…" } },
  { "inline_data": { "mime_type": "image/jpeg", "data": "…base64 photo 2…" } },
  …
]
```

Le raccourci actuel ne fabrique **qu'un seul** bloc `inline_data`. Il faut donc :

1. Sélectionner/prendre **plusieurs** photos.
2. **Boucler** sur chaque photo pour créer son bloc `inline_data`.
3. **Concaténer** ces blocs (séparés par des virgules).
4. Les injecter dans le JSON, après le bloc `text`.

Tout le reste (appel à l'URL, extraction de la réponse, copie) reste identique.

---

## 2. Étapes exactes dans l'app Raccourcis

### Étape 1 — Choisir plusieurs photos

Remplace **« Prendre 1 photo »** par l'une de ces deux options :

- **« Sélectionner des photos »** avec l'option **« Sélectionner plusieurs »
  activée** → tu prends d'abord toutes les photos du logement avec l'appareil
  photo, puis tu lances le raccourci et tu les sélectionnes. *(Recommandé, plus
  souple.)*
- Ou garde **« Prendre des photos »** et règle le **nombre** > 1 si tu préfères
  tout faire à la volée.

Le résultat de cette action est une **liste de photos**.

### Étape 2 — Boucle qui construit les blocs image

Ajoute **« Répéter pour chaque »** en lui passant la liste de photos.
**À l'intérieur** de la boucle, place ces actions dans cet ordre :

1. **Redimensionner** l'image → passe **« Élément de répétition »**, Taille = `1024`,
   Hauteur automatique.
2. **Convertir** l'image redimensionnée **en JPEG**.
3. **Encoder** l'image convertie **en Base64**
   → ⚠️ **ouvre les options et DÉSACTIVE « Sauts de ligne »** (sinon le base64
   contient des retours à la ligne qui cassent le JSON).
4. **Texte** — colle exactement ceci (le champ bleu = la sortie « Codé en Base64 ») :

   ```
   {"inline_data":{"mime_type":"image/jpeg","data":"[Codé en Base64]"}}
   ```

5. **Ajouter à une variable** → nom de la variable : `PartsImages`
   (ajoute le **Texte** de l'étape 4 à cette variable à chaque tour de boucle).

### Étape 3 — Assembler les blocs

**Après** la boucle, ajoute :

- **« Combiner le texte »** → texte = variable `PartsImages`, **séparateur =
  virgule personnalisée `,`**. On obtient `bloc1,bloc2,bloc3…`.

### Étape 4 — Construire le corps de la requête

Action **Texte** (remplace ton ancien bloc JSON). Le champ bleu = la sortie de
« Combiner le texte » :

```
{"contents":[{"parts":[{"text":"COLLE_ICI_TON_PROMPT"},[Texte combiné]]}],"generationConfig":{"temperature":0.2,"maxOutputTokens":4096}}
```

> Le `[Texte combiné]` s'insère **juste après** le bloc `{"text":…}`, séparé par
> une virgule. Comme il contient déjà `{…},{…}`, le tableau `parts` devient bien
> `[ {text}, {img1}, {img2}, … ]`.

`generationConfig` est optionnel mais conseillé avec plusieurs photos :
- `temperature: 0.2` → réponses stables et factuelles.
- `maxOutputTokens: 4096` → évite que le descriptif soit **coupé** quand il y a
  beaucoup de pièces.

### Étape 5 — Le reste ne change pas

- **Obtenir le contenu de** `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent?key=…`
  (méthode **POST**, en‑tête `Content-Type: application/json`, corps = le Texte de
  l'étape 4).
- **Obtenir la valeur** pour la clé `candidates.1.content.parts.1.text`.
- **Copier** dans le presse‑papiers.
- **Afficher la notification** / le résultat.

---

## 3. Prompt réécrit (multi‑photos)

Reprends ton prompt existant et **ajoute la phrase de consolidation** au début.
Voici une version complète que tu peux adapter (garde-la sur **une seule ligne**,
sans vrai retour à la ligne ni guillemets droits `"` à l'intérieur) :

> Tu es un assistant qui rédige des états des lieux. Les images fournies montrent
> le **même logement sous plusieurs angles** (plusieurs photos par pièce). Produis
> **un seul descriptif consolidé** : ne décris **pas deux fois** le même élément
> vu sur plusieurs photos, et regroupe logiquement par zone. Liste les éléments
> visibles (sols, murs, plafond, menuiseries, équipements…). Regroupe les éléments
> identiques (ex : 3 spots), mais ne compte pas les prises ni les interrupteurs.
> Une ligne courte par élément, au format : **Élément (matière) — État : Mauvais /
> État d'usage / Bon / Très bon**. N'indique pas la matière pour les appareils
> électriques et électroniques. Juge l'état avec neutralité, sans indulgence ni
> sévérité systématique, en utilisant les quatre niveaux selon ce que tu vois
> réellement. Quand tu indiques *État d'usage* ou *Mauvais*, précise en Observation
> ce qui le justifie avec « — Observation : … », en le situant. N'écris aucune
> Observation si aucun défaut n'est nettement visible. N'invente rien, pas
> d'introduction ni de conclusion, une ligne vide entre chaque élément. En français.

⚠️ Dans le JSON, le texte du prompt ne doit contenir **aucun guillemet droit `"`**
ni vrai saut de ligne. Les « guillemets français », les tirets — et les apostrophes
' sont sans danger.

---

## 4. Points d'attention

- **Sauts de ligne du Base64** : bien les **désactiver** (étape 2.3). C'est la
  cause n°1 d'erreur « invalid JSON / invalid argument ».
- **Taille de la requête** : Gemini accepte jusqu'à ~20 Mo de données *inline*.
  Une photo en 1024 px ≈ 100–300 Ko en base64, donc **~10 à 15 photos** passent
  sans problème. Au‑delà, il faudrait passer par la *Files API* (plus complexe).
- **Clé API visible** : ta clé `key=…` est écrite en clair dans l'URL. Si tu
  **partages** le raccourci, tu partages ta clé. Ne la diffuse pas, et si besoin
  régénère‑la dans Google AI Studio.
- **Modèle** : `gemini-flash-lite-latest` est rapide et peu coûteux. Si tu veux un
  descriptif plus fin, teste `gemini-2.5-flash` (mêmes étapes, change juste le nom
  du modèle dans l'URL).
- **Coller dans Nokee** : le résultat étant dans le presse‑papiers, tu peux le
  coller **n'importe où** (Nokee, Notes, mail…). Rien à changer côté raccourci.

---

## 5. Schéma récapitulatif du raccourci

```
Sélectionner des photos (multiple)
│
├─ Répéter pour chaque (Photo)
│    ├─ Redimensionner  → 1024
│    ├─ Convertir en JPEG
│    ├─ Encoder Base64  (sans sauts de ligne)
│    ├─ Texte : {"inline_data":{"mime_type":"image/jpeg","data":"[Base64]"}}
│    └─ Ajouter à la variable  PartsImages
│
├─ Combiner le texte  PartsImages  (séparateur : ,)
│
├─ Texte : {"contents":[{"parts":[{"text":"PROMPT"},[Texte combiné]]}],
│           "generationConfig":{"temperature":0.2,"maxOutputTokens":4096}}
│
├─ Obtenir le contenu de l'URL  (POST, Gemini)
├─ Obtenir la valeur  candidates.1.content.parts.1.text
├─ Copier dans le presse-papiers
└─ Afficher la notification
```
