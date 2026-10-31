import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";

import { d1 } from "./d1.mjs";
import * as tsLoader from "./ts-loader.mjs";

registerHooks({ resolve: tsLoader.resolve });
const { list, get } = await import("../src/routes/products.ts");

const SCHEMA = [
  "../migrations/0001_init.sql",
  "../migrations/0002_reward_email_hash_and_file_sha256.sql",
]
  .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
  .join("\n");

const NOW = "2026-01-01T00:00:00.000Z";

/** `count` products, each with one image; the last one is delisted. */
function seeded(count) {
  const db = d1(SCHEMA);
  for (let i = 0; i < count; i++) {
    const active = i === count - 1 ? 0 : 1;
    db.raw.exec(`INSERT INTO products (id, name, cost, active, type, created_at, updated_at)
                 VALUES ('p${i}', 'Product ${i}', 10, ${active}, 'key', '${NOW}', '${NOW}')`);
    db.raw.exec(`INSERT INTO product_images (id, product_id, object_key, position, created_at)
                 VALUES ('i${i}', 'p${i}', 'https://cdn.test/${i}.jpg', 0, '${NOW}')`);
  }
  return db;
}

function ctx(db, id = "", isAdmin = false, query = "") {
  const url = new URL(`https://api.test/v1/products${query}`);
  return {
    req: new Request(url),
    env: { DB: db, PUBLIC_CDN: "" },
    url,
    requestId: "test",
    params: { id },
    user: isAdmin ? { id: "admin", email: "a@test.dev", coins: 0, isAdmin: true } : null,
  };
}

test("list attaches images for products past the first parameter chunk", async () => {
  const db = seeded(120); // 3 chunks of 50

  const body = await (await list(ctx(db))).json();

  assert.equal(body.products.length, 119); // the delisted one is hidden
  for (const p of body.products) {
    const n = p.id.slice(1);
    assert.deepEqual(p.imageUrls, [`https://cdn.test/${n}.jpg`], p.id);
  }
});

test("get hides a delisted product from buyers and shows it to admins", async () => {
  const db = seeded(2); // p1 is delisted

  await assert.rejects(get(ctx(db, "p1")), (e) => e.status === 404);

  const body = await (await get(ctx(db, "p1", true))).json();
  assert.equal(body.product.id, "p1");
});
