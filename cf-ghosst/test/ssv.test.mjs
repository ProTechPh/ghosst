import assert from "node:assert/strict";
import test from "node:test";
import { createSign, generateKeyPairSync } from "node:crypto";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";

import { d1 } from "./d1.mjs";
import * as tsLoader from "./ts-loader.mjs";

registerHooks({ resolve: tsLoader.resolve });
const { derToRaw, ssv } = await import("../src/routes/ads.ts");
const { sha256Hex } = await import("../src/lib/auth.ts");

const content = new TextEncoder().encode("user_id=u1&reward_amount=10&transaction_id=t1");

/** AdMob signs with a P-256 key and sends the signature DER-encoded. */
async function signed() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const der = new Uint8Array(createSign("SHA256").update(content).sign(privateKey));
  const key = await crypto.subtle.importKey(
    "spki",
    publicKey.export({ type: "spki", format: "der" }),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return { der, key };
}

const verify = (key, sig) =>
  crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, sig, content);

test("derToRaw yields the 64-byte signature WebCrypto actually verifies", async () => {
  const { der, key } = await signed();

  const raw = derToRaw(der);
  assert.equal(raw.length, 64);
  assert.equal(await verify(key, raw), true);
});

test("derToRaw output no longer verifies once a byte is flipped", async () => {
  const { der, key } = await signed();
  const raw = derToRaw(der);

  for (const at of [0, 31, 32, 63]) {
    const bad = raw.slice();
    bad[at] ^= 0x01;
    assert.equal(await verify(key, bad), false, `byte ${at}`);
  }
});

test("derToRaw strips the DER sign padding that makes r or s 33 bytes", () => {
  // r with a leading 0x00 (high bit set), s short: both must be left-padded to 32.
  const der = Uint8Array.from([0x30, 0x27, 0x02, 0x21, 0x00, ...new Array(32).fill(0xaa), 0x02, 0x02, 0x01, 0x02]);
  const raw = derToRaw(der);
  assert.equal(raw.length, 64);
  assert.equal(raw[0], 0xaa); // the 0x00 padding is stripped, not copied
  assert.equal(raw[62], 0x01);
  assert.equal(raw[63], 0x02);
});

test("derToRaw rejects a blob that is not a DER SEQUENCE", () => {
  assert.throws(() => derToRaw(Uint8Array.from([0x31, 0x00])), /bad DER/);
  assert.throws(() => derToRaw(Uint8Array.from([0x30, 0x02, 0x05, 0x00])), /bad DER/);
});

// ---- the credit path, with Google's key server stubbed out -----------------

const SCHEMA = [
  "../migrations/0001_init.sql",
  "../migrations/0002_reward_email_hash_and_file_sha256.sql",
]
  .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
  .join("\n");

// Google's verifier keys are fetched and cached per isolate, so one keypair
// serves every callback below. The stub runs before the first SSV call.
const KEY = generateKeyPairSync("ec", { namedCurve: "P-256" });
const SPKI = KEY.publicKey.export({ type: "spki", format: "der" }).toString("base64");
globalThis.fetch = async () =>
  new Response(JSON.stringify({ keys: [{ keyId: 1, base64: SPKI }] }), { status: 200 });

/** Signs a callback the way AdMob does. */
async function signedCallback(db, fields) {
  const signed = Object.entries(fields)
    .map(([k, v]) => `${k}=${v}`)
    .join("&");
  const signature = createSign("SHA256").update(signed).sign(KEY.privateKey).toString("base64");
  const url = new URL(`https://api.test/v1/ads/ssv?${signed}&signature=${encodeURIComponent(signature)}&key_id=1`);

  await ssv({
    req: new Request(url),
    env: { DB: db, JWT_SECRET: "s" },
    url,
    requestId: "test",
    params: {},
    user: null,
  });
}

function seeded() {
  const db = d1(SCHEMA);
  db.raw.exec(`INSERT INTO users (id, email, password_hash, display_name, coins, created_at)
               VALUES ('u1', 'Farmer@Test.dev', 'x', '', 0, '2026-01-01T00:00:00.000Z')`);
  return db;
}

const coins = (db) => db.raw.prepare(`SELECT coins FROM users WHERE id = 'u1'`).get().coins;

test("a verified callback credits coins and hashes the payer's email", async () => {
  const db = seeded();

  await signedCallback(db, {
    ad_unit: "ca-app-pub-7791552060229072/3206073177",
    reward_amount: 10,
    transaction_id: "tx-1",
    user_id: "u1",
  });

  assert.equal(coins(db), 10);
  const row = db.raw.prepare(`SELECT email_hash FROM ad_rewards WHERE id = 'tx-1'`).get();
  assert.equal(row.email_hash, await sha256Hex("farmer@test.dev")); // lowercased
});

test("a second callback inside the cooldown pays nothing and leaves no row", async () => {
  const db = seeded();
  const unit = "ca-app-pub-7791552060229072/3206073177";

  await signedCallback(db, { ad_unit: unit, reward_amount: 10, transaction_id: "tx-1", user_id: "u1" });
  await signedCallback(db, { ad_unit: unit, reward_amount: 10, transaction_id: "tx-2", user_id: "u1" });

  assert.equal(coins(db), 10);
  assert.deepEqual(
    db.raw.prepare(`SELECT id FROM ad_rewards ORDER BY id`).all().map((r) => r.id),
    ["tx-1"],
  );
});
