/**
 * Appwrite Function: reward-ssv
 *
 * Google AdMob server-side verification (SSV) callback target. Verifies the
 * signed reward callback from Google and credits coins to the user's profile.
 *
 * Real callbacks : GET/POST with ?signature=<RS256 JWS>... (from AdMob)
 * Debug path     : SDK execution with body { "action": "simulate" } — only
 *                  while the function env var DEBUG_REWARDS=1.
 *
 * Env vars:
 *   DEBUG_REWARDS      = "1" to enable the simulate path (remove for release)
 *   COINS_PER_REWARD   = fallback coins if reward_amount is not numeric (10)
 *   PROJECT / endpoint below are hardcoded to this project.
 */

const crypto = require('crypto');

const ENDPOINT = 'https://sgp.cloud.appwrite.io/v1';
const PROJECT = '6ac4baef0010879da982';
const DB = 'ghosst';
const COL = { profiles: 'profiles', adRewards: 'ad_rewards' };

const GOOGLE_CERTS_URL = 'https://www.googleapis.com/identity/v1/certs';
const MAX_EVENT_AGE_MS = 48 * 60 * 60 * 1000; // reject very old callbacks

/** Minimal Appwrite REST helper (ephemeral key auth). */
async function api(method, path, { key, body, queries } = {}) {
  const url = new URL(ENDPOINT + path);
  if (queries) url.searchParams.set('queries', JSON.stringify(queries));
  const headers = { 'content-type': 'application/json' };
  headers['x-appwrite-project'] = PROJECT;
  if (key) headers['x-appwrite-key'] = key;

  const res = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_) {
    data = { message: text };
  }
  if (!res.ok) {
    const err = new Error((data && data.message) || `HTTP ${res.status}`);
    err.status = res.status;
    err.payload = data;
    throw err;
  }
  return data;
}

/** Collect query/body params regardless of GET or POST delivery. */
function collectParams(req) {
  const out = {};
  try {
    const u = new URL(req.url || '/', 'http://localhost');
    for (const [k, v] of u.searchParams.entries()) out[k] = v;
  } catch (_) {}
  if (req.bodyJson && typeof req.bodyJson === 'object') {
    Object.assign(out, req.bodyJson);
  }
  if (!out.signature && req.bodyText) {
    try {
      for (const [k, v] of new URLSearchParams(req.bodyText)) out[k] = v;
    } catch (_) {}
  }
  return out;
}

/** Normalize Google's cert response (array, {key:[...]}, or JWKS). */
function certsFrom(json) {
  if (Array.isArray(json)) return json;
  if (Array.isArray(json.key)) return json.key;
  if (Array.isArray(json.keys)) {
    return json.keys
      .filter((k) => Array.isArray(k.x5c) && k.x5c[0])
      .map((k) => {
        const b64 = k.x5c[0].replace(/(.{64})/g, '$1\n');
        return `-----BEGIN CERTIFICATE-----\n${b64}\n-----END CERTIFICATE-----\n`;
      });
  }
  return [];
}

/** Verify the AdMob SSV JWS against Google's certificates. Returns payload. */
async function verifySignature(signature) {
  const parts = String(signature).split('.');
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;

  let header;
  try {
    header = JSON.parse(Buffer.from(h, 'base64url').toString('utf8'));
  } catch (_) {
    return null;
  }
  if (header.alg !== 'RS256') return null;

  const certRes = await fetch(GOOGLE_CERTS_URL);
  if (!certRes.ok) throw new Error(`cert fetch failed: ${certRes.status}`);
  const certs = certsFrom(await certRes.json());
  if (certs.length === 0) throw new Error('no certs available');

  const data = Buffer.from(`${h}.${p}`, 'utf8');
  const sig = Buffer.from(s, 'base64url');
  for (const cert of certs) {
    try {
      const pub = crypto.createPublicKey(cert);
      if (crypto.verify('RSA-SHA256', data, pub, sig)) {
        return JSON.parse(Buffer.from(p, 'base64url').toString('utf8'));
      }
    } catch (_) {
      /* try next cert */
    }
  }
  return null;
}

/** Turn an arbitrary string into a valid Appwrite document id. */
function docIdFrom(raw) {
  const id = String(raw).replace(/[^A-Za-z0-9._-]/g, '').slice(0, 36);
  return id.length > 0 ? id : null;
}

/** Create the profile doc on first reward. */
async function ensureProfile(key, uid) {
  try {
    const p = await api(
      'GET',
      `/databases/${DB}/collections/${COL.profiles}/documents/${uid}`,
      { key },
    );
    return p;
  } catch (e) {
    if (e.status !== 404) throw e;
    await api('POST', `/databases/${DB}/collections/${COL.profiles}/documents`, {
      key,
      body: {
        documentId: uid,
        data: { coins: 0, displayName: '' },
        permissions: [`read("user:${uid}")`],
      },
    });
    return null;
  }
}

/** Credit coins to a user's profile. */
async function credit(key, uid, amount) {
  const profile = await ensureProfile(key, uid);
  const current = profile ? Number(profile.data.coins || 0) : 0;
  const next = current + amount;
  if (profile) {
    await api(
      'PATCH',
      `/databases/${DB}/collections/${COL.profiles}/documents/${uid}`,
      {
        key,
        body: { data: { coins: next }, permissions: [`read("user:${uid}")`] },
      },
    );
  } else {
    await api('POST', `/databases/${DB}/collections/${COL.profiles}/documents`, {
      key,
      body: {
        documentId: uid,
        data: { coins: next, displayName: '' },
        permissions: [`read("user:${uid}")`],
      },
    });
  }
  return next;
}

module.exports = async (context) => {
  const { req, res, log, error } = context;
  const key = req.headers['x-appwrite-key'];
  if (!key) {
    error('Missing ephemeral API key — set function scopes in the console.');
    return res.json(
      { ok: false, error: 'Function not configured (missing scopes)' },
      500,
    );
  }

  const params = collectParams(req);

  try {
    // ---- Debug path: simulate a rewarded ad (DEBUG_REWARDS=1 only) ----
    if (params.action === 'simulate') {
      if (process.env.DEBUG_REWARDS !== '1') {
        return res.json(
          { ok: false, error: 'DEBUG_REWARDS is disabled on this function' },
          403,
        );
      }
      const jwt = req.headers['x-appwrite-user-jwt'];
      if (!jwt) {
        return res.json({ ok: false, error: 'Not signed in' }, 401);
      }
      const url = new URL(ENDPOINT + '/account');
      const r = await fetch(url, {
        headers: {
          'x-appwrite-project': PROJECT,
          'x-appwrite-jwt': jwt,
        },
      });
      if (!r.ok) {
        return res.json({ ok: false, error: 'Not signed in' }, 401);
      }
      const user = await r.json();
      const amount = parseInt(process.env.COINS_PER_REWARD || '10', 10) || 10;
      const total = await credit(key, user.$id, amount);
      log(`simulate reward user=${user.$id} +${amount} total=${total}`);
      return res.json({ ok: true, reward: amount, coins: total });
    }

    // ---- Real AdMob SSV callback ----
    const signature = params.signature;
    if (!signature) {
      return res.text('missing signature', 400);
    }

    const payload = await verifySignature(signature);
    if (!payload) {
      error('SSV signature verification failed');
      return res.text('bad signature', 403);
    }

    // Basic claim sanity checks.
    if (payload.iss && payload.iss !== 'https://www.google.com') {
      error(`bad iss: ${payload.iss}`);
      return res.text('bad issuer', 403);
    }
    if (payload.exp && payload.exp * 1000 < Date.now()) {
      error('SSV token expired');
      return res.text('expired', 403);
    }
    if (payload.event_time) {
      const t = Date.parse(payload.event_time);
      if (!Number.isNaN(t) && Date.now() - t > MAX_EVENT_AGE_MS) {
        error(`stale event_time: ${payload.event_time}`);
        return res.text('stale', 403);
      }
    }

    const uid = payload.user_id || params.user_id;
    if (!uid) {
      error('SSV callback missing user_id (ad loaded without SSV options?)');
      return res.text('missing user_id', 400);
    }

    let amount = parseInt(payload.reward_amount, 10);
    if (Number.isNaN(amount) || amount <= 0) {
      amount = parseInt(process.env.COINS_PER_REWARD || '10', 10) || 10;
    }

    // Idempotency: AdMob includes a unique nonce per callback.
    const dedupeKey =
      docIdFrom(payload.nonce || payload.jti || '') ||
      docIdFrom(`${uid}-${payload.event_time || Date.now()}`) ||
      `cb-${Date.now()}`;

    // Try to record the callback first — duplicate = already credited.
    try {
      await api('POST', `/databases/${DB}/collections/${COL.adRewards}/documents`, {
        key,
        body: {
          documentId: dedupeKey,
          data: {
            userId: uid,
            reward: amount,
            nonce: String(payload.nonce || ''),
            adUnit: String(payload.ad_unit || ''),
            eventTime: String(payload.event_time || ''),
            createdAt: new Date().toISOString(),
          },
        },
      });
    } catch (e) {
      if (e.status === 409) {
        log(`duplicate SSV callback ignored (${dedupeKey})`);
        return res.text('ok', 200);
      }
      throw e;
    }

    const total = await credit(key, uid, amount);
    log(`reward user=${uid} +${amount} total=${total} nonce=${dedupeKey}`);
    return res.text('ok', 200);
  } catch (e) {
    error(e && e.stack ? e.stack : String(e));
    return res.text('error', 500);
  }
};
