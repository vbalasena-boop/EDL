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
 *   - Variable (option)  ALLOW_ORIGIN = l'URL de ton app (sinon "*" en test)
 *
 * Une entrée LICENSES : clé = la clé d'accès du client ; valeur (JSON) =
 *   { "plan":"mensuel", "limit":100000, "used":0, "expires":"2027-01-01" }
 *   ("limit": nombre d'analyses autorisées ; "expires": date ISO ou null)
 */

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

export default {
  async fetch(request, env) {
    const origin = env.ALLOW_ORIGIN || '*';
    const cors = {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-License',
    };

    // Préflight CORS
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });

    const url = new URL(request.url);
    const json = (obj, status = 200) =>
      new Response(JSON.stringify(obj), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

    const license = (request.headers.get('X-License') || '').trim();
    if (!license) return json({ error: 'Clé d’accès manquante.' }, 401);

    // Lit la license dans le stockage
    let rec;
    try { rec = await env.LICENSES.get(license, 'json'); } catch (e) { rec = null; }
    if (!rec) return json({ error: 'Clé d’accès invalide.' }, 403);
    if (rec.expires && new Date(rec.expires) < new Date())
      return json({ error: 'Abonnement expiré.' }, 403);

    const used = rec.used || 0;
    const limit = rec.limit || 0;
    const remaining = Math.max(0, limit - used);

    // Endpoint d'info : GET /me → état de la license
    if (request.method === 'GET' && url.pathname.endsWith('/me')) {
      return json({ valid: true, plan: rec.plan || '', used, limit, remaining, expires: rec.expires || null });
    }

    if (request.method !== 'POST') return json({ error: 'Méthode non autorisée.' }, 405);
    if (remaining <= 0) return json({ error: 'Quota atteint. Renouvelle ton abonnement.' }, 402);

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
