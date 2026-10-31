import type { Ctx } from "../index";
import { sha256Hex } from "../lib/auth";
import {
  contentId,
  isOurRewardedUnit,
  rewardVerdict,
  DEFAULT_LIMITS,
} from "../lib/rewards";

const KEY_SERVER = "https://gstatic.com/admob/reward/verifier-keys.json";
const KEY_TTL_MS = 6 * 60 * 60 * 1000;
const MAX_AGE_MS = 48 * 60 * 60 * 1000;
/** Ceiling on a single callback, so one bad AdMob setting cannot mint. */
const MAX_REWARD = 1000;

type VerifierKey = { keyId: string; key: CryptoKey };
let cache: { at: number; keys: VerifierKey[] } | null = null;

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64.replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function pemToDer(pem: string): Uint8Array {
  return b64ToBytes(pem.replace(/-----(BEGIN|END) PUBLIC KEY-----/g, "").replace(/\s+/g, ""));
}

async function loadKeys(): Promise<VerifierKey[]> {
  if (cache && Date.now() - cache.at < KEY_TTL_MS) return cache.keys;

  const res = await fetch(KEY_SERVER);
  if (!res.ok) throw new Error(`AdMob key server HTTP ${res.status}`);
  const body = (await res.json()) as {
    keys?: Array<{ keyId: string | number; pem?: string; base64?: string }>;
  };

  const keys: VerifierKey[] = [];
  for (const k of body.keys ?? []) {
    const pem =
      k.pem ??
      (k.base64 ? `-----BEGIN PUBLIC KEY-----\n${k.base64}\n-----END PUBLIC KEY-----` : "");
    if (!pem) continue;
    keys.push({
      keyId: String(k.keyId),
      key: await crypto.subtle.importKey(
        "spki",
        pemToDer(pem),
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["verify"],
      ),
    });
  }

  if (keys.length === 0) throw new Error("AdMob key server returned no keys");
  cache = { at: Date.now(), keys };
  return keys;
}

/**
 * DER SEQUENCE{INTEGER r, INTEGER s} → 64-byte r‖s.
 * WebCrypto ECDSA expects IEEE P1363 (raw), AdMob sends DER. Node's
 * crypto.verify hides this; this port cannot.
 */
export function derToRaw(der: Uint8Array): Uint8Array {
  let i = 0;
  if (der[i++] !== 0x30) throw new Error("bad DER: expected SEQUENCE");

  let len = der[i++];
  if (len & 0x80) {
    const n = len & 0x7f;
    len = 0;
    for (let k = 0; k < n; k++) len = (len << 8) | der[i++];
  }

  const readInt = (): Uint8Array => {
    if (der[i++] !== 0x02) throw new Error("bad DER: expected INTEGER");
    const l = der[i++];
    let v = der.slice(i, i + l);
    i += l;
    while (v.length > 32 && v[0] === 0) v = v.slice(1); // strip sign padding
    const out = new Uint8Array(32);
    out.set(v, 32 - v.length);
    return out;
  };

  const r = readInt();
  const s = readInt();
  const out = new Uint8Array(64);
  out.set(r, 0);
  out.set(s, 32);
  return out;
}

/** GET /v1/ads/ssv?...&signature=...&key_id=... */
export async function ssv(ctx: Ctx): Promise<Response> {
  const ok = () => new Response("ok", { status: 200 });

  const qs = ctx.url.search.replace(/^\?/, "");
  const marker = /(?:^|&)signature=/.exec(qs);
  if (!marker) return ok();

  // Google signs the raw query string up to (but not including) &signature=.
  const content = marker[0] === "&signature=" ? qs.slice(0, marker.index) : "";
  const rest = qs.slice(marker.index + marker[0].length);
  const tail = /^([^&]*)&key_id=([^&]*)/.exec(rest);
  if (!tail) return ok();

  let keys: VerifierKey[];
  try {
    keys = await loadKeys();
  } catch (err) {
    console.error(`[${ctx.requestId}] SSV key load failed`, err);
    return ok();
  }

  const entry = keys.find((k) => k.keyId === decodeURIComponent(tail[2]));
  if (!entry) {
    console.error(`[${ctx.requestId}] SSV unknown key_id ${tail[2]}`);
    return ok();
  }

  const verified = await crypto.subtle
    .verify(
      { name: "ECDSA", hash: "SHA-256" },
      entry.key,
      derToRaw(b64ToBytes(decodeURIComponent(tail[1]))),
      new TextEncoder().encode(content),
    )
    .catch(() => false);

  if (!verified) {
    console.error(`[${ctx.requestId}] SSV signature mismatch`);
    return ok();
  }

  const params = ctx.url.searchParams;
  const uid = params.get("user_id");
  if (!uid) return ok();

  const timestamp = params.get("timestamp") ?? "";
  if (timestamp) {
    let t = Number(timestamp);
    if (!Number.isFinite(t)) t = Date.parse(timestamp);
    if (Number.isFinite(t) && t > 1e14) t = Math.floor(t / 1000); // µs → ms
    if (Number.isFinite(t) && t > 0 && Date.now() - t > MAX_AGE_MS) return ok();
  }

  // Our inventory only. A callback signed for a stranger's ad unit means they
  // pointed their own AdMob account at this Worker — Google vouches for the
  // signature, not for who earned the impression.
  const adUnit = params.get("ad_unit") ?? "";
  if (!isOurRewardedUnit(adUnit)) {
    console.warn(`[${ctx.requestId}] SSV blocked: foreign ad_unit ${adUnit} user=${uid}`);
    return ok();
  }

  let amount = parseInt(params.get("reward_amount") ?? "", 10);
  if (!Number.isFinite(amount) || amount <= 0) {
    amount = parseInt(ctx.env.COINS_PER_REWARD ?? "10", 10) || 10;
  }
  if (amount > MAX_REWARD) amount = MAX_REWARD;

  // Google always sends transaction_id; hash the signed payload when it does
  // not, so a replay still lands on the same primary key instead of a new one.
  const txId = params.get("transaction_id") || (await contentId(content));
  const now = new Date();

  // Pacing identity: the email hash survives account deletion (see
  // account.remove), so a delete + re-register cannot restart the daily budget.
  const account = await ctx.env.DB.prepare(`SELECT email FROM users WHERE id = ?1`)
    .bind(uid)
    .first<{ email: string }>();
  const emailHash = account?.email ? await sha256Hex(account.email.trim().toLowerCase()) : null;

  // Dedupe first: the primary key IS the transaction id.
  const fresh = await ctx.env.DB.prepare(
    `INSERT INTO ad_rewards (id, user_id, reward, ad_unit, event_time, created_at, email_hash)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) ON CONFLICT DO NOTHING RETURNING id`,
  )
    .bind(txId, uid, amount, adUnit, timestamp, now.toISOString(), emailHash)
    .first<{ id: string }>();

  if (!fresh) return ok(); // duplicate callback — already credited

  // Pace per account, enforced server-side: the cooldown in the app lives in
  // a file the farmer can patch. The row just inserted counts itself, so the
  // insert (serialised by its primary key) is what decides a race.
  const windowStart = new Date(now.getTime() - DEFAULT_LIMITS.windowMs).toISOString();
  const state = await ctx.env.DB.prepare(
    `SELECT COUNT(*) AS n, MAX(CASE WHEN id <> ?2 THEN created_at END) AS last
       FROM ad_rewards
      WHERE created_at >= ?3
        AND ((?4 IS NOT NULL AND email_hash = ?4)
             OR (email_hash IS NULL AND user_id = ?1))`,
  )
    .bind(uid, txId, windowStart, emailHash)
    .first<{ n: number; last: string | null }>();

  const verdict = rewardVerdict(
    { count: state?.n ?? 0, lastAt: state?.last ?? null },
    now,
  );
  if (!verdict.ok) {
    // Drop the ledger row: nothing was paid, so it must not count against the
    // cap or appear in the wallet history. Google already got its 200.
    await ctx.env.DB.prepare(`DELETE FROM ad_rewards WHERE id = ?1`).bind(txId).run();
    console.warn(
      `[${ctx.requestId}] SSV blocked: ${verdict.reason} user=${uid} ad_unit=${adUnit}`,
    );
    return ok();
  }

  try {
    const credited = await ctx.env.DB.prepare(
      `UPDATE users SET coins = coins + ?1 WHERE id = ?2 RETURNING coins`,
    )
      .bind(amount, uid)
      .first<{ coins: number }>();

    if (!credited) {
      // Unknown user (deleted?) — drop the ledger row so a later retry works.
      await ctx.env.DB.prepare(`DELETE FROM ad_rewards WHERE id = ?1`).bind(txId).run();
    }
  } catch (err) {
    await ctx.env.DB.prepare(`DELETE FROM ad_rewards WHERE id = ?1`).bind(txId).run();
    // 500 so Google retries — never return 200 on a failed credit.
    console.error(`[${ctx.requestId}] SSV credit failed`, err);
    return new Response("error", { status: 500 });
  }

  return ok();
}
