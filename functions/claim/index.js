/**
 * Appwrite Function: claim  (single combined function)
 *
 * Routes on the request:
 *   - query ?signature=<AdMob SSV signature>               -> verified reward callback
 *   - body { action: "simulate" }                          -> rejected (debug path removed)
 *   - body { productId }                                   -> license claim
 *
 * Called by the Flutter app via Functions.createExecution (synchronous) and
 * by Google AdMob via the function's HTTP domain URL.
 *
 * Caller identity : x-appwrite-user-jwt header (forwarded by Appwrite)
 * Privileged DB   : x-appwrite-key header (ephemeral API key — configure
 *                   scopes: documents.read, documents.write in the console)
 *
 * Env vars: COINS_PER_REWARD (fallback reward when callback omits reward_amount)
 *
 * Returns: { ok: true, key } | { ok: false, error }   (claim)
 *          text "ok" | "error" ...                    (SSV, per Google spec)
 */

const crypto = require('crypto');

const ENDPOINT = 'https://sgp.cloud.appwrite.io/v1';
const PROJECT = '6ac4baef0010879da982';
const DB = 'ghosst';

const COL = {
  profiles: 'profiles',
  products: 'products',
  keys: 'keys',
  claims: 'claims',
  adRewards: 'ad_rewards',
};

const GOOGLE_CERTS_URL = 'https://www.googleapis.com/identity/v1/certs';
// Modern AdMob SSV keys (ECDSA P-256) — https://developers.google.com/admob/android/ssv
const ADMOB_KEY_SERVER = 'https://gstatic.com/admob/reward/verifier-keys.json';
const KEY_CACHE_MS = 6 * 60 * 60 * 1000; // docs: never cache longer than 24h
const MAX_EVENT_AGE_MS = 48 * 60 * 60 * 1000; // reject very old callbacks

/** Minimal Appwrite REST helper. */
async function api(method, path, { jwt, key, body, queries } = {}) {
  const url = new URL(ENDPOINT + path);
  if (queries && queries.length) {
    // Appwrite REST expects each query as its own `queries[]` element
    // (same format the official SDKs use: key + "[]" for List GET params).
    // Sending one JSON-encoded string instead fails the query validator
    // with "value must be a valid array ...".
    for (const q of queries) url.searchParams.append('queries[]', q);
  }
  const headers = { 'content-type': 'application/json' };
  headers['x-appwrite-project'] = PROJECT;
  // REST API accepts JWTs via X-Appwrite-JWT (distinct from the
  // x-appwrite-user-jwt header Appwrite passes *into* functions).
  if (jwt) headers['x-appwrite-jwt'] = jwt;
  if (key) headers['x-appwrite-key'] = key;

  const res = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data = null;
  try {
    data = text && text.trim() ? JSON.parse(text) : null;
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
  // bodyJson may be a lazily-parsed getter — an empty body can throw
  // "Unexpected end of JSON input", so never let it escape.
  try {
    const bj = req.bodyJson;
    if (bj && typeof bj === 'object') Object.assign(out, bj);
  } catch (_) {}
  try {
    if (!out.signature && req.bodyText) {
      for (const [k, v] of new URLSearchParams(req.bodyText)) out[k] = v;
    }
  } catch (_) {}
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

/** Raw query string exactly as received (order/content must not change —
 *  it is the data Google's ECDSA signature covers). */
function rawQuery(req) {
  const u = String(req.url || '');
  const i = u.indexOf('?');
  return i >= 0 ? u.slice(i + 1) : '';
}

/** Fetch AdMob's ECDSA public keys (cached for up to 6 hours). */
let keyCache = { at: 0, list: null };

function pemFromBase64(b64) {
  const body = String(b64).replace(/(.{64})/g, '$1\n').trim();
  return `-----BEGIN PUBLIC KEY-----\n${body}\n-----END PUBLIC KEY-----`;
}

async function admobKeys() {
  if (keyCache.list && Date.now() - keyCache.at < KEY_CACHE_MS) {
    return keyCache.list;
  }
  const r = await fetch(ADMOB_KEY_SERVER);
  if (!r.ok) throw new Error(`AdMob key server HTTP ${r.status}`);
  const j = await r.json();
  const list = (Array.isArray(j.keys) ? j.keys : [])
    .filter((k) => k && (k.pem || k.base64))
    .map((k) => ({ keyId: String(k.keyId), pem: k.pem || pemFromBase64(k.base64) }));
  if (list.length === 0) throw new Error('AdMob key server returned no keys');
  keyCache = { at: Date.now(), list };
  return list;
}

/** Verify a modern AdMob SSV callback.
 *  Content to verify = raw query string up to (excluding) "&signature=".
 *  Signature = ECDSA-SHA256 (DER), key selected by the key_id param.
 *  Spec: https://developers.google.com/admob/android/ssv */
async function verifyEcdsaQuery(qs) {
  const m = /(?:^|&)signature=/.exec(qs);
  if (!m) return { ok: false, reason: 'no signature param in query' };

  const preceded = m[0] === '&signature=';
  const content = preceded ? qs.slice(0, m.index) : '';
  const rest = qs.slice(m.index + m[0].length);

  let sigB64 = null;
  let keyId = null;
  const km = /^([^&]*)&key_id=([^&]*)/.exec(rest);
  if (km) {
    sigB64 = km[1];
    keyId = km[2];
  } else {
    sigB64 = rest.split('&')[0];
    const kf = /(?:^|&)key_id=([^&]*)/.exec(qs);
    if (kf) keyId = kf[1];
  }
  if (!sigB64 || !keyId) {
    return { ok: false, reason: 'missing signature/key_id params' };
  }

  const keys = await admobKeys();
  const entry = keys.find((k) => k.keyId === String(keyId));
  if (!entry) return { ok: false, reason: `unknown key_id ${keyId}` };

  let pub;
  try {
    pub = crypto.createPublicKey(entry.pem);
  } catch (_) {
    return { ok: false, reason: 'unparsable public key' };
  }
  const data = Buffer.from(content, 'utf8');
  const sig = Buffer.from(
    sigB64.replace(/-/g, '+').replace(/_/g, '/'),
    'base64',
  );
  // Node's default dsaEncoding is 'der' — matches Tink's EcdsaEncoding.DER.
  const ok = crypto.verify('sha256', data, pub, sig);
  return { ok, reason: ok ? '' : 'signature mismatch' };
}

/** CORS headers for browser callers (AdMob console preflight/verify).
 *  Appwrite's domain edge has no CORS config and forwards OPTIONS straight
 *  to the function, so preflights must be answered here. */
function corsHeaders(req) {
  const h = (req && req.headers) || {};
  const requested = h['access-control-request-headers'];
  return {
    'Access-Control-Allow-Origin': h.origin || '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers':
      requested ||
      'Content-Type, Authorization, X-Appwrite-JWT, X-Appwrite-Key, X-Appwrite-Project',
    'Access-Control-Max-Age': '3600',
  };
}

/** Turn an arbitrary string into a valid Appwrite document id. */
function docIdFrom(raw) {
  const id = String(raw).replace(/[^A-Za-z0-9._-]/g, '').slice(0, 36);
  return id.length > 0 ? id : null;
}

/** Appwrite-friendly random id (36 chars max, [A-Za-z0-9._-]). */
function apiId() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Create the profile doc on first reward. */
async function ensureProfile(key, uid) {
  try {
    return await api(
      'GET',
      `/databases/${DB}/collections/${COL.profiles}/documents/${uid}`,
      { key },
    );
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
  let profile = await ensureProfile(key, uid);
  if (!profile) {
    // ensureProfile just created it — read back for the current balance
    // (avoid a second POST, which would collide with the first: 409).
    profile = await api(
      'GET',
      `/databases/${DB}/collections/${COL.profiles}/documents/${uid}`,
      { key },
    );
  }
  // REST GET returns the document fields at the top level (no .data wrapper;
  // .data only appears in create/update request bodies).
  const next = Number(profile.coins || 0) + amount;
  await api(
    'PATCH',
    `/databases/${DB}/collections/${COL.profiles}/documents/${uid}`,
    {
      key,
      body: { data: { coins: next }, permissions: [`read("user:${uid}")`] },
    },
  );
  return next;
}

/* ------------------------------------------------------------------ */
/* Claim: spend coins, assign the oldest available key                 */
/* ------------------------------------------------------------------ */

async function handleClaim(context, key, params) {
  const { req, res, log, error } = context;

  const jwt = req.headers['x-appwrite-user-jwt'];
  if (!jwt) {
    return res.json({ ok: false, error: 'Not signed in' }, 200);
  }

  const productId = params.productId;
  if (!productId) {
    return res.json({ ok: false, error: 'Missing productId' }, 200);
  }

  // 1. Who is calling?
  const user = await api('GET', '/account', { jwt });
  const uid = user.$id;

  // 2. Load product.
  let product;
  try {
    product = await api(
      'GET',
      `/databases/${DB}/collections/${COL.products}/documents/${productId}`,
      { key },
    );
  } catch (e) {
    if (e.status === 404) {
      return res.json({ ok: false, error: 'Product not found' }, 200);
    }
    throw e;
  }
  if (product.active === false) {
    return res.json({ ok: false, error: 'Product disabled' }, 200);
  }
  const cost = Number(product.cost || 0);

  // 3. Load profile (coins).
  let coins = 0;
  let profileExists = true;
  try {
    const p = await api(
      'GET',
      `/databases/${DB}/collections/${COL.profiles}/documents/${uid}`,
      { key },
    );
    coins = Number(p.coins || 0);
  } catch (e) {
    if (e.status === 404) profileExists = false;
    else throw e;
  }

  if (coins < cost) {
    return res.json(
      { ok: false, error: `Not enough coins (need ${cost}, have ${coins})` },
      200,
    );
  }

  // 4. Pick the oldest available key.
  const list = await api(
    'GET',
    `/databases/${DB}/collections/${COL.keys}/documents`,
    {
      key,
      queries: [
        // Modern Appwrite expects JSON query objects (see appwrite lib/query.dart)
        JSON.stringify({ method: 'equal', attribute: 'productId', values: [productId] }),
        JSON.stringify({ method: 'equal', attribute: 'status', values: ['available'] }),
        JSON.stringify({ method: 'orderAsc', attribute: '$createdAt' }),
        JSON.stringify({ method: 'limit', values: [1] }),
      ],
    },
  );
  if (!list.documents || list.documents.length === 0) {
    return res.json({ ok: false, error: 'Out of stock' }, 200);
  }
  const keyDoc = list.documents[0];
  const keyText = keyDoc.key;

  const now = new Date().toISOString();

  // 5. Mark key claimed.
  await api(
    'PATCH',
    `/databases/${DB}/collections/${COL.keys}/documents/${keyDoc.$id}`,
    {
      key,
      body: {
        data: { status: 'claimed', claimedBy: uid, claimedAt: now },
      },
    },
  );

  // 6. Deduct coins (create profile on first claim).
  if (!profileExists) {
    await api('POST', `/databases/${DB}/collections/${COL.profiles}/documents`, {
      key,
      body: {
        documentId: uid,
        data: { coins: Math.max(0, coins - cost), displayName: user.name || '' },
        permissions: [`read("user:${uid}")`],
      },
    });
  } else {
    await api(
      'PATCH',
      `/databases/${DB}/collections/${COL.profiles}/documents/${uid}`,
      {
        key,
        body: {
          data: { coins: coins - cost },
          permissions: [`read("user:${uid}")`],
        },
      },
    );
  }

  // 7. Record the claim (readable only by the owner).
  await api('POST', `/databases/${DB}/collections/${COL.claims}/documents`, {
    key,
    body: {
      documentId: apiId(),
      data: {
        userId: uid,
        productId,
        productName: product.name || '',
        keyId: keyDoc.$id,
        keyText,
        cost,
        createdAt: now,
      },
      permissions: [`read("user:${uid}")`],
    },
  });

  log(`claim ok user=${uid} product=${productId} cost=${cost}`);
  return res.json({ ok: true, key: keyText, cost });
}

/* ------------------------------------------------------------------ */
/* Reward: AdMob SSV callback                                          */
/* ------------------------------------------------------------------ */

async function handleReward(context, key, params) {
  const { req, res, log, error } = context;

  try {
    // ---- Legacy debug path: removed. Reject cleanly (app-facing 200). ----
    if (params.action === 'simulate') {
      return res.json({ ok: false, error: 'Simulate is disabled' }, 200);
    }

    // ---- Real AdMob SSV callback ----
    // Modern format: ECDSA signature over the raw query string, public key
    // fetched from the AdMob key server (developers.google.com/admob/android/ssv).
    // Legacy format: RS256 JWS — still supported when signature has dots.
    const signature = params.signature;
    if (!signature) {
      error('SSV callback missing signature');
      return res.text('ok', 200);
    }

    let verified = false;
    let legacy = null;
    if (signature.indexOf('.') !== -1) {
      legacy = await verifySignature(signature);
      verified = !!legacy;
      if (verified && legacy.iss && legacy.iss !== 'https://www.google.com') {
        error(`bad iss: ${legacy.iss}`);
        verified = false;
      }
      if (verified && legacy.exp && legacy.exp * 1000 < Date.now()) {
        error('SSV token expired');
        verified = false;
      }
    } else {
      const r = await verifyEcdsaQuery(rawQuery(req));
      verified = r.ok;
      if (!verified) error(`SSV verification failed: ${r.reason}`);
    }
    if (!verified) {
      // Google expects 200 OK (it retries non-200s) — acknowledge the
      // callback but NEVER credit coins for an unverified signature.
      return res.text('ok', 200);
    }

    const uid = params.user_id || (legacy && legacy.user_id);
    if (!uid) {
      error('SSV callback missing user_id (ad loaded without SSV options?)');
      return res.text('ok', 200);
    }

    let amount = parseInt(
      params.reward_amount || (legacy && legacy.reward_amount),
      10,
    );
    if (Number.isNaN(amount) || amount <= 0) {
      amount = parseInt(process.env.COINS_PER_REWARD || '10', 10) || 10;
    }

    // Staleness guard: timestamp is epoch ms (sometimes µs), legacy used ISO.
    const tsRaw = params.timestamp || (legacy && legacy.event_time) || '';
    if (tsRaw) {
      let t = Number(tsRaw);
      if (Number.isNaN(t)) t = Date.parse(tsRaw);
      if (!Number.isNaN(t) && t > 1e14) t = Math.floor(t / 1000); // µs → ms
      if (!Number.isNaN(t) && t > 0 && Date.now() - t > MAX_EVENT_AGE_MS) {
        error(`stale callback timestamp: ${tsRaw}`);
        return res.text('ok', 200);
      }
    }

    const txId =
      params.transaction_id ||
      (legacy && (legacy.transaction_id || legacy.nonce || legacy.jti)) ||
      '';

    // Idempotency: one ad_rewards document per reward grant.
    const dedupeKey =
      docIdFrom(txId) ||
      docIdFrom(`${uid}-${tsRaw || Date.now()}`) ||
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
            nonce: String(txId || ''),
            adUnit: String(params.ad_unit || ''),
            eventTime: String(tsRaw || ''),
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
    // Unexpected failure: 500 lets Google retry the callback (up to 5×).
    return res.text('error', 500);
  }
}

/* ------------------------------------------------------------------ */
/* Embed page                                                          */
/* ------------------------------------------------------------------ */

/** HTML wrapper for the in-app product video (served at ?yt=<id>).
 *  The document origin is this function's real domain; the iframe uses
 *  youtube-nocookie.com with origin= matching the document. */
function ytEmbedHtml(id) {
  return `<!DOCTYPE html>
<html>
<head>
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <style>
    html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
    iframe { border: 0; width: 100%; height: 100%; display: block; }
  </style>
</head>
<body>
  <iframe
    src="https://www.youtube-nocookie.com/embed/${id}?playsinline=1&rel=0&origin=https%3A%2F%2Fclaim.sgp.appwrite.run"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
    referrerpolicy="strict-origin-when-cross-origin"
    allowfullscreen></iframe>
</body>
</html>`;
}

/* ------------------------------------------------------------------ */
/* Router                                                              */
/* ------------------------------------------------------------------ */

module.exports = async (context) => {
  const { req, res, log, error } = context;

  const cors = corsHeaders(req);

  // Diagnostic: record the raw request line so callback debugging can tell
  // AdMob's payload apart from test probes (truncated to keep logs tidy).
  try {
    log(`${req.method || '?'} ${String(req.url || '').slice(0, 300)}`);
  } catch (_) {}

  // Browser preflight must be answered before anything else (no auth/keys).
  if ((req.method || '').toUpperCase() === 'OPTIONS') {
    return res.json({ ok: true }, 200, cors);
  }

  // Params are needed up-front for the embed route below (and reused by the
  // claim/reward routes further down).
  let params = {};
  try {
    params = collectParams(req);
  } catch (_) {}

  // In-app product video: GET ?yt=<id> serves the embed wrapper as REAL
  // HTML from this third-party origin. YouTube's embedded player rejects
  // data:/about:blank documents (Error 153) and faked same-origin
  // documents (Error 152-4) — a genuine external site origin is what a
  // normal website embed looks like. iframe uses youtube-nocookie.com
  // (reported to bypass the 152-4 origin check).
  if (params.yt && /^[A-Za-z0-9_-]{11}$/.test(params.yt)) {
    return res.text(ytEmbedHtml(params.yt), 200, {
      'Content-Type': 'text/html; charset=utf-8',
      ...cors,
    });
  }

  // Wrap res so every handler response carries the CORS headers
  // (Appwrite Functions: res.json(data, code, headers)).
  context.res = {
    json: (data, code) => res.json(data, code, cors),
    text: (body, code) => res.text(body, code, cors),
    empty: (code) => res.empty(code, cors),
  };

  const key = req.headers['x-appwrite-key'];
  if (!key) {
    error('Missing ephemeral API key — set function scopes in the console.');
    return res.json(
      { ok: false, error: 'Function not configured (missing scopes)' },
      200,
      cors,
    );
  }

  try {
    if (params.signature || params.action === 'simulate') {
      return await handleReward(context, key, params);
    }
    return await handleClaim(context, key, params);
  } catch (e) {
    error(e && e.stack ? e.stack : String(e));
    return res.json(
      { ok: false, error: (e && e.message) || 'Function failed' },
      200,
      cors,
    );
  }
};
