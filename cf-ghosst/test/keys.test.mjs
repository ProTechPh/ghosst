import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";

import { d1 } from "./d1.mjs";
import * as tsLoader from "./ts-loader.mjs";

registerHooks({ resolve: tsLoader.resolve });
const { list, clearForProduct } = await import("../src/routes/keys.ts");

const SCHEMA = [
  "../migrations/0001_init.sql",
  "../migrations/0002_reward_email_hash_and_file_sha256.sql",
]
  .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
  .join("\n");

const NOW = "2026-01-01T00:00:00.000Z";

/** Two products: p1 has 3 available + 1 claimed, p2 has 1 available (7d only). */
function seeded() {
  const db = d1(SCHEMA);
  for (const id of ["p1", "p2"]) {
    db.raw.exec(`INSERT INTO products (id, name, cost, active, type, created_at, updated_at)
                 VALUES ('${id}', '${id}', 10, 1, 'key', '${NOW}', '${NOW}')`);
  }
  const rows = [
    ["k1", "p1", "available", ""],
    ["k2", "p1", "available", ""],
    ["k3", "p1", "available", ""],
    ["k4", "p1", "claimed", ""],
    ["k5", "p2", "available", "7d"],
  ];
  for (const [id, product, status, duration] of rows) {
    db.raw.exec(`INSERT INTO keys (id, product_id, key_value, status, duration, created_at)
                 VALUES ('${id}', '${product}', 'KEY-${id}', '${status}', '${duration}', '${NOW}')`);
  }
  return db;
}

function ctx(db, query, params = {}) {
  const url = new URL(`https://api.test/v1/admin/keys${query}`);
  return {
    req: new Request(url),
    env: { DB: db, PUBLIC_CDN: "" },
    url,
    requestId: "test",
    params,
    user: { id: "admin", email: "a@test.dev", coins: 0, isAdmin: true },
  };
}

test("count mode answers with one number, filtered by product, status and duration", async () => {
  const db = seeded();

  const read = async (query) => (await (await list(ctx(db, query))).json()).total;

  assert.equal(await read("?count=1"), 5);
  assert.equal(await read("?count=1&productId=p1"), 4);
  assert.equal(await read("?count=1&productId=p1&status=available"), 3);
  assert.equal(await read("?count=1&productId=p2&status=available&duration=7d"), 1);
  assert.equal(await read("?count=1&productId=p2&status=available&duration=30d"), 0);
});

test("list filters use the same WHERE as the count", async () => {
  const db = seeded();

  const body = await (await list(ctx(db, "?productId=p1&status=available"))).json();
  assert.deepEqual(body.keys.map((k) => k.id).sort(), ["k1", "k2", "k3"]);
  assert.equal(body.total, 3);

  const capped = await (await list(ctx(db, "?limit=2"))).json();
  assert.equal(capped.keys.length, 2);
});

test("clearing a product's stock honours the optional status filter", async () => {
  const db = seeded();

  const awarded = await (await clearForProduct(ctx(db, "?status=claimed", { id: "p1" }))).json();
  assert.equal(awarded.deleted, 1);
  assert.equal(db.raw.prepare(`SELECT COUNT(*) AS n FROM keys`).get().n, 4);

  const all = await (await clearForProduct(ctx(db, "", { id: "p1" }))).json();
  assert.equal(all.deleted, 3);
  assert.equal(db.raw.prepare(`SELECT COUNT(*) AS n FROM keys`).get().n, 1);
});
