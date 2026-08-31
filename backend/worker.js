/**
 * EDL IA — Serveur (Cloudflare Worker)
 * -------------------------------------
 * Rôle : cacher la clé Gemini, vérifier la clé d'accès (license) du client,
 * compter les usages (quota), et relayer la requête à Gemini.
 *
 * Le client n'a JAMAIS la clé Gemini : il envoie seulement sa clé d'accès.
 *
 * Réglages à définir dans le tableau de bord Cloudflare :
 *   - Variable secrète  GEMINI_KEY   = ta clé Google Gemini (AIza...)
 *   - Namespace KV       LICENSES     = stocke les clés d'accès des clients
 *   - Variable           ALLOW_ORIGIN = l'URL de ton app (ex : https://vbalasena-boop.github.io)
 *                                       Recommandé : active le verrou d'origine (#3).
 *                                       Laisse vide/"*" seulement en test.
 *   - Variable secrète  STRIPE_KEY    = ta clé SECRÈTE Stripe (sk_live_... ou sk_test_...)
 *                                       Sert à créer la clé automatiquement après paiement.
 *                                       (Endpoint GET /checkout?session_id=cs_...)
 *   - Variable secrète  STRIPE_WEBHOOK_SECRET = le "signing secret" (whsec_...) du webhook Stripe.
 *                                       Sert au renouvellement mensuel auto des abonnements.
 *                                       (Endpoint POST /webhook ; événement invoice.paid)
 *
 * Sécurité incluse :
 *   #1 Verrou multi-appareils : une clé n'accepte que "maxDevices" appareils (défaut 2 ;
 *      plan "admin" = illimité). Pour réinitialiser : remets "devices":[] dans l'entrée KV.
 *   #2 Limite de débit : 20 analyses / minute par clé (protège la facture IA).
 *   #3 Verrou d'origine : si ALLOW_ORIGIN ≠ "*", la clé ne marche que depuis ton app.
 *
 * Une entrée LICENSES : clé = la clé d'accès du client ; valeur (JSON) =
 *   { "plan":"mensuel", "limit":100000, "used":0, "expires":"2027-01-01" }
 *   ("limit": nombre d'analyses autorisées ; "expires": date ISO ou null)
 */

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

/* ---- Stripe : création automatique de clé après paiement ---- */
// Associe le montant payé (en centimes) à une formule.
// Adapte ici si tu changes tes prix.
function planFromAmount(cents) {
  switch (cents) {
    case 1900: return { plan: 'solo',     limit: 400,     maxDevices: 2, months: 1 };
    case 3900: return { plan: 'pro',      limit: 1200,    maxDevices: 2, months: 1 };
    case 7900: return { plan: 'illimite', limit: 9999999, maxDevices: 3, months: 1 };
    case 900:  return { plan: 'pack',     limit: 200,     maxDevices: 2, months: 3 };
    default:   return null;
  }
}
function rand4() {
  const A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sans I,O,0,1 (lisibilité)
  let s = ''; for (let i = 0; i < 4; i++) s += A[Math.floor(Math.random() * A.length)];
  return s;
}
function buildLicense(p) {
  const d = new Date(); d.setMonth(d.getMonth() + p.months);
  return { plan: p.plan, limit: p.limit, used: 0, maxDevices: p.maxDevices,
           expires: d.toISOString().slice(0, 10), devices: [] };
}
async function handleCheckout(url, env, json) {
  const sid = (url.searchParams.get('session_id') || '').trim();
  if (!/^cs_[A-Za-z0-9_]+$/.test(sid)) return json({ error: 'Session invalide.' }, 400);
  if (!env.STRIPE_KEY) return json({ error: 'Paiement non configuré.' }, 500);
  // Déjà traité ? (idempotence) → renvoie la clé existante
  let existing = null;
  try { existing = await env.LICENSES.get('sess:' + sid); } catch (e) {}
  if (existing) return json({ key: existing });
  // Récupère la session Stripe et vérifie le paiement
  let sess;
  try {
    const r = await fetch('https://api.stripe.com/v1/checkout/sessions/' + encodeURIComponent(sid) + '?expand[]=line_items',
      { headers: { Authorization: 'Bearer ' + env.STRIPE_KEY } });
    sess = await r.json();
    if (!r.ok) return json({ error: 'Session introuvable.' }, 404);
  } catch (e) { return json({ error: 'Service de paiement injoignable.' }, 502); }
  const paid = sess.payment_status === 'paid' || sess.status === 'complete';
  if (!paid) return json({ pending: true });
  // Montant robuste (paiement unique OU abonnement)
  let amount = sess.amount_total || sess.amount_subtotal || 0;
  const li = sess.line_items && sess.line_items.data && sess.line_items.data[0];
  if (!amount && li) amount = li.amount_total || (li.price && li.price.unit_amount) || 0;
  const plan = planFromAmount(amount);
  if (!plan) return json({ error: 'Formule non reconnue.' }, 400);
  const key = 'IMS-' + rand4() + '-' + rand4();
  try {
    await env.LICENSES.put(key, JSON.stringify(buildLicense(plan)));
    await env.LICENSES.put('sess:' + sid, key); // mémorise pour idempotence + relecture
    // Abonnement : lie l'ID d'abonnement à la clé (pour le renouvellement auto via webhook)
    if (sess.subscription) await env.LICENSES.put('sub:' + sess.subscription, key);
  } catch (e) { return json({ error: 'Création de la clé impossible.' }, 500); }
  return json({ key });
}

/* ---- Webhook Stripe : renouvellement mensuel automatique des abonnements ---- */
async function verifyStripe(payload, sigHeader, secret) {
  try {
    const parts = {};
    (sigHeader || '').split(',').forEach(kv => { const i = kv.indexOf('='); if (i > 0) parts[kv.slice(0, i)] = kv.slice(i + 1); });
    if (!parts.t || !parts.v1) return false;
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const sig = await crypto.subtle.sign('HMAC', key, enc.encode(parts.t + '.' + payload));
    const hex = [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, '0')).join('');
    if (hex.length !== (parts.v1 || '').length) return false;
    let diff = 0; for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ parts.v1.charCodeAt(i);
    return diff === 0;
  } catch (e) { return false; }
}
async function handleWebhook(request, env) {
  if (!env.STRIPE_WEBHOOK_SECRET) return new Response('webhook non configuré', { status: 500 });
  const payload = await request.text();
  const ok = await verifyStripe(payload, request.headers.get('Stripe-Signature'), env.STRIPE_WEBHOOK_SECRET);
  if (!ok) return new Response('signature invalide', { status: 400 });
  let evt; try { evt = JSON.parse(payload); } catch (e) { return new Response('json invalide', { status: 400 }); }
  if (evt.type === 'invoice.paid' || evt.type === 'invoice.payment_succeeded') {
    const inv = evt.data && evt.data.object;
    // Uniquement les RENOUVELLEMENTS (le 1er paiement est géré par /checkout)
    if (inv && inv.billing_reason === 'subscription_cycle' && inv.subscription) {
      try {
        const key = await env.LICENSES.get('sub:' + inv.subscription);
        if (key) {
          const rec = await env.LICENSES.get(key, 'json');
          if (rec) {
            const d = new Date(); d.setMonth(d.getMonth() + 1);
            rec.expires = d.toISOString().slice(0, 10); // prolonge d'un mois
            rec.used = 0;                                // quota remis à zéro
            await env.LICENSES.put(key, JSON.stringify(rec));
          }
        }
      } catch (e) {}
    }
  }
  return new Response('ok', { status: 200 });
}

export default {
  async fetch(request, env) {
    const origin = env.ALLOW_ORIGIN || '*';
    const cors = {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-License, X-Device',
    };

    // Préflight CORS
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });

    const url = new URL(request.url);
    const json = (obj, status = 200) =>
      new Response(JSON.stringify(obj), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

    // Webhook Stripe (serveur à serveur) : AVANT le verrou d'origine (pas d'en-tête Origin).
    if (request.method === 'POST' && url.pathname.endsWith('/webhook')) {
      return handleWebhook(request, env);
    }

    // #3 Verrou d'origine : si ALLOW_ORIGIN est défini (≠ "*"), la clé ne
    // fonctionne que depuis ton app. Un Origin absent (appel non-navigateur) ou
    // différent est refusé. (Protection contre les autres sites/apps ; un client
    // non-navigateur peut toujours forger l'en-tête — d'où la clé d'accès en plus.)
    if (origin !== '*') {
      const reqOrigin = request.headers.get('Origin') || '';
      if (reqOrigin !== origin) return json({ error: 'Origine non autorisée.' }, 403);
    }

    // Endpoint public d'achat : après paiement Stripe, crée/renvoie la clé.
    // Appelé par la page « Merci » (merci.html) avec ?session_id=cs_...
    if (request.method === 'GET' && url.pathname.endsWith('/checkout')) {
      return handleCheckout(url, env, json);
    }

    const license = (request.headers.get('X-License') || '').trim();
    if (!license) return json({ error: 'Clé d’accès manquante.' }, 401);

    // Lit la license dans le stockage
    let rec;
    try { rec = await env.LICENSES.get(license, 'json'); } catch (e) { rec = null; }
    if (!rec) return json({ error: 'Clé d’accès invalide.' }, 403);
    if (rec.expires && new Date(rec.expires) < new Date())
      return json({ error: 'Abonnement expiré.' }, 403);

    // #1 Verrou multi-appareils (anti-partage de clé)
    // Une clé n'accepte qu'un nombre limité d'appareils distincts.
    //   - rec.maxDevices : nombre max d'appareils (défaut 2 ; 0 = illimité)
    //   - plan "admin"   : toujours illimité (ta clé perso)
    // Pour réinitialiser les appareils d'un client : remets "devices":[] dans son entrée KV.
    const DEFAULT_MAX_DEVICES = 2;
    const maxDevices = (rec.plan === 'admin') ? 0
      : (typeof rec.maxDevices === 'number' ? rec.maxDevices : DEFAULT_MAX_DEVICES);
    if (maxDevices > 0) {
      const device = (request.headers.get('X-Device') || '').trim().slice(0, 64);
      if (device) {
        let devices = Array.isArray(rec.devices) ? rec.devices : [];
        if (!devices.includes(device)) {
          if (devices.length >= maxDevices)
            return json({ error: `Clé déjà utilisée sur ${maxDevices} appareils. Contacte le support pour la réinitialiser.` }, 403);
          devices.push(device);
          rec.devices = devices;
          try { await env.LICENSES.put(license, JSON.stringify(rec)); } catch (e) {}
        }
      }
    }

    const used = rec.used || 0;
    const limit = rec.limit || 0;
    const remaining = Math.max(0, limit - used);

    // Endpoint d'info : GET /me → état de la license
    if (request.method === 'GET' && url.pathname.endsWith('/me')) {
      return json({ valid: true, plan: rec.plan || '', used, limit, remaining, expires: rec.expires || null });
    }

    if (request.method !== 'POST') return json({ error: 'Méthode non autorisée.' }, 405);
    if (remaining <= 0) return json({ error: 'Quota atteint. Renouvelle ton abonnement.' }, 402);

    // #2 Limite de débit : 20 analyses / minute par clé (protège ta facture IA).
    // Fenêtre fixe d'une minute, stockée dans KV avec expiration auto (~2 min).
    const RL_MAX = 20;
    const rlKey = 'rl:' + license + ':' + Math.floor(Date.now() / 60000);
    let rlCount = 0;
    try { rlCount = parseInt(await env.LICENSES.get(rlKey)) || 0; } catch (e) {}
    if (rlCount >= RL_MAX)
      return json({ error: 'Trop de requêtes. Patiente une minute avant de relancer.' }, 429);
    try { await env.LICENSES.put(rlKey, String(rlCount + 1), { expirationTtl: 120 }); } catch (e) {}

    // Corps envoyé par l'app : { model, contents, generationConfig }
    let payload;
    try { payload = await request.json(); } catch (e) { return json({ error: 'Requête invalide.' }, 400); }
    const model = (payload.model || 'gemini-flash-lite-latest').replace(/[^a-z0-9.\-]/gi, '');
    const body = { contents: payload.contents, generationConfig: payload.generationConfig || { temperature: 0.2, maxOutputTokens: 2048 } };

    // Appel à Gemini avec la clé cachée côté serveur
    let data;
    try {
      const res = await fetch(`${GEMINI_BASE}/${model}:generateContent?key=${env.GEMINI_KEY}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      });
      data = await res.json();
      if (!res.ok) return json({ error: (data && data.error && data.error.message) || 'Erreur du service IA.' }, 502);
    } catch (e) {
      return json({ error: 'Service IA injoignable.' }, 502);
    }

    const cand = data.candidates && data.candidates[0];
    let text = '';
    if (cand && cand.content && cand.content.parts) text = cand.content.parts.map(p => p.text).filter(Boolean).join('\n').trim();
    if (!text) return json({ error: 'Réponse vide de l’IA.' }, 502);

    // Incrémente l'usage (best-effort)
    try { rec.used = used + 1; await env.LICENSES.put(license, JSON.stringify(rec)); } catch (e) {}

    return json({ text, remaining: Math.max(0, limit - (used + 1)) });
  },
};
