import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";

import { d1 } from "./d1.mjs";
import * as tsLoader from "./ts-loader.mjs";

// Register before the dynamic import: src modules import each other without
// file extensions, which Node ESM cannot resolve on its own.
registerHooks({ resolve: tsLoader.resolve });
const { claim } = await import("../src/routes/claims.ts");

const SCHEMA = [
  "../migrations/0001_init.sql",
  "../migrations/0002_reward_email_hash_and_file_sha256.sql",
]
  .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
  .join("\n");

const NOW = "2026-01-01T00:00:00.000Z";

function seed(db, { coins = 50, keys = 0, cost = 50, type = "key", file = null } = {}) {
  db.raw.exec(`INSERT INTO users (id, email, password_hash, display_name, coins, created_at)
               VALUES ('u1', 'u1@test.dev', 'x', '', ${coins}, '${NOW}')`);
  db.raw.exec(`INSERT INTO products (id, name, cost, active, type, created_at, updated_at)
               VALUES ('p1', 'License', ${cost}, 1, '${type}', '${NOW}', '${NOW}')`);
  for (let i = 0; i < keys; i++) {
    db.raw.exec(`INSERT INTO keys (id, product_id, key_value, status, duration, created_at)
                 VALUES ('k${i}', 'p1', 'KEY-${i}', 'available', '', '${NOW}')`);
  }
  if (file) {
    db.raw.prepare(
      `INSERT INTO product_files (product_id, object_key, filename, size, sha256, updated_at)
       VALUES ('p1', ?, 'app.apk', 123, ?, ?)`,
    ).run(file, "a".repeat(64), NOW);
  }
}

function ctx(db, body, idemKey) {
  return {
    req: new Request("https://api.test/v1/claims", {
      method: "POST",
      headers: { "idempotency-key": idemKey, "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
    env: { DB: db, JWT_SECRET: "test-secret", PUBLIC_CDN: "" },
    url: new URL("https://api.test/v1/claims"),
    requestId: "test",
    params: {},
    user: { id: "u1", email: "u1@test.dev", coins: 0, isAdmin: false },
  };
}

const coins = (db) => db.raw.prepare(`SELECT coins FROM users WHERE id = 'u1'`).get().coins;
const keyStatus = (db) => db.raw.prepare(`SELECT status FROM keys WHERE id = 'k0'`).get().status;
const count = (db, table) =>
  db.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n;

test("a claim with empty stock charges nothing and clears its reservation", async () => {
  const db = d1(SCHEMA);
  seed(db, { coins: 50, keys: 0 });

  await assert.rejects(claim(ctx(db, { productId: "p1" }, "idem-1")), (e) => e.code === "out_of_stock");

  assert.equal(coins(db), 50);
  assert.equal(count(db, "claims"), 0);
  assert.equal(count(db, "idempotency"), 0);
});

test("a claim that cannot pay hands the key back and keeps the balance", async () => {
  const db = d1(SCHEMA);
  seed(db, { coins: 10, keys: 1, cost: 50 });

  await assert.rejects(
    claim(ctx(db, { productId: "p1" }, "idem-2")),
    (e) => e.code === "insufficient_coins",
  );

  assert.equal(coins(db), 10);
  assert.equal(keyStatus(db), "available");
  assert.equal(count(db, "claims"), 0);
});

test("a paid claim charges once, records it and replays without recharging", async () => {
  const db = d1(SCHEMA);
  seed(db, { coins: 50, keys: 1, cost: 50 });

  const first = await claim(ctx(db, { productId: "p1" }, "idem-3"));
  const body = await first.json();
  assert.equal(first.status, 200);
  assert.equal(body.key, "KEY-0");
  assert.equal(body.cost, 50);
  assert.equal(body.coins, 0);
  assert.equal(coins(db), 0);
  assert.equal(keyStatus(db), "claimed");
  assert.equal(count(db, "claims"), 1);

  // Same Idempotency-Key: the stored response, no second charge, no second key.
  const replay = await claim(ctx(db, { productId: "p1" }, "idem-3"));
  assert.equal(replay.status, 200);
  assert.deepEqual(await replay.json(), body);
  assert.equal(coins(db), 0);
  assert.equal(count(db, "claims"), 1);
});

test("a download claim charges, records and never charges twice", async () => {
  const db = d1(SCHEMA);
  seed(db, { coins: 50, cost: 30, type: "file", file: "https://cdn.test/app.apk" });

  const first = await claim(ctx(db, { productId: "p1" }, "idem-4"));
  const body = await first.json();
  assert.equal(first.status, 200);
  assert.equal(body.alreadyOwned, false);
  assert.equal(body.downloadUrl, "https://cdn.test/app.apk");
  assert.equal(body.sha256, "a".repeat(64));
  assert.equal(coins(db), 20);
  assert.equal(count(db, "claims"), 1);

  const again = await claim(ctx(db, { productId: "p1" }, "idem-5"));
  const second = await again.json();
  assert.equal(again.status, 200);
  assert.equal(second.alreadyOwned, true);
  assert.equal(second.cost, 30);
  assert.equal(coins(db), 20);
  assert.equal(count(db, "claims"), 1);
});

test("a download claim that cannot pay records nothing and keeps the balance", async () => {
  const db = d1(SCHEMA);
  seed(db, { coins: 10, cost: 30, type: "file", file: "https://cdn.test/app.apk" });

  await assert.rejects(
    claim(ctx(db, { productId: "p1" }, "idem-6")),
    (e) => e.code === "insufficient_coins",
  );

  assert.equal(coins(db), 10);
  assert.equal(count(db, "claims"), 0);
});
