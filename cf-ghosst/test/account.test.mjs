import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";

import { d1 } from "./d1.mjs";
import * as tsLoader from "./ts-loader.mjs";

registerHooks({ resolve: tsLoader.resolve });
const { remove } = await import("../src/routes/account.ts");

const SCHEMA = [
  "../migrations/0001_init.sql",
  "../migrations/0002_reward_email_hash_and_file_sha256.sql",
]
  .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
  .join("\n");

const NOW = "2026-01-01T00:00:00.000Z";
const uid = "u1";

function seeded() {
  const db = d1(SCHEMA);
  db.raw.exec(`INSERT INTO users (id, email, password_hash, display_name, coins, created_at)
               VALUES ('${uid}', 'u1@test.dev', 'x', 'Jo', 5, '${NOW}')`);
  db.raw.exec(`INSERT INTO products (id, name, cost, type, created_at, updated_at)
               VALUES ('p1', 'License', 10, 'key', '${NOW}', '${NOW}')`);
  db.raw.exec(`INSERT INTO keys (id, product_id, key_value, status, claimed_by, claimed_at, created_at)
               VALUES ('k1', 'p1', 'KEY-1', 'claimed', '${uid}', '${NOW}', '${NOW}')`);
  db.raw.exec(`INSERT INTO claims (id, user_id, product_id, key_id, key_text, cost, created_at)
               VALUES ('c1', '${uid}', 'p1', 'k1', 'KEY-1', 10, '${NOW}')`);
  db.raw.exec(`INSERT INTO ad_rewards (id, user_id, reward, created_at)
               VALUES ('t1', '${uid}', 10, '${NOW}')`);
  db.raw.exec(`INSERT INTO idempotency (user_id, key, response, created_at)
               VALUES ('${uid}', 'i1', '{}', '${NOW}')`);
  return db;
}

function ctx(db) {
  return {
    req: new Request("https://api.test/v1/account", {
      method: "DELETE",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ confirm: "DELETE" }),
    }),
    env: { DB: db },
    url: new URL("https://api.test/v1/account"),
    requestId: "test",
    params: {},
    user: { id: uid, email: "u1@test.dev", coins: 5, isAdmin: false },
  };
}

const rows = (db, sql) => db.raw.prepare(sql).all().length;

test("deletion returns claimed keys to the shelf instead of stranding them", async () => {
  const db = seeded();

  assert.equal((await remove(ctx(db))).status, 200);

  const key = db.raw.prepare(`SELECT status, claimed_by, claimed_at FROM keys WHERE id = 'k1'`).get();
  assert.equal(key.status, "available");
  assert.equal(key.claimed_by, null);
  assert.equal(key.claimed_at, null);
});

test("deletion keeps the ad ledger — it is what stops the daily cap resetting", async () => {
  const db = seeded();

  await remove(ctx(db));

  assert.equal(rows(db, `SELECT * FROM ad_rewards`), 1);
  assert.equal(rows(db, `SELECT * FROM claims`), 0);
  assert.equal(rows(db, `SELECT * FROM idempotency`), 0);
  const user = db.raw.prepare(`SELECT email, password_hash, deleted_at FROM users`).get();
  assert.ok(user.deleted_at);
  assert.equal(user.password_hash, "");
  assert.notEqual(user.email, "u1@test.dev");
});
