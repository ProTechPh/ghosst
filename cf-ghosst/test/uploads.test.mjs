import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";

import { d1 } from "./d1.mjs";
import * as tsLoader from "./ts-loader.mjs";

registerHooks({ resolve: tsLoader.resolve });
const { complete } = await import("../src/routes/uploads.ts");

const SCHEMA = [
  "../migrations/0001_init.sql",
  "../migrations/0002_reward_email_hash_and_file_sha256.sql",
]
  .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
  .join("\n");

const NOW = "2026-01-01T00:00:00.000Z";
const SHA = "a".repeat(64);

function ctx(db, body) {
  return {
    req: new Request("https://api.test/v1/uploads/complete", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
    env: {
      DB: db,
      // Stand-in for the R2 binding: `head` is all complete() reads.
      BUCKET: {
        head: async () => ({ size: 1, etag: "e", httpMetadata: { contentType: "application/zip" } }),
        delete: async () => {},
      },
    },
    url: new URL("https://api.test/v1/uploads/complete"),
    requestId: "test",
    params: {},
    user: { id: "admin", email: "a@test.dev", coins: 0, isAdmin: true },
  };
}

function body(sha256) {
  return {
    objectKey: "product-files/p1/x.zip",
    productId: "p1",
    kind: "file",
    filename: "x.zip",
    expectedSize: 1,
    expectedType: "application/zip",
    sha256,
  };
}

function seeded() {
  const db = d1(SCHEMA);
  db.raw.exec(`INSERT INTO products (id, name, cost, active, type, created_at, updated_at)
               VALUES ('p1', 'App', 10, 1, 'file', '${NOW}', '${NOW}')`);
  return db;
}

test("uploads/complete accepts only 64 lowercase hex characters for sha256", async () => {
  for (const bad of [
    SHA.toUpperCase(),
    "a".repeat(63),
    "a".repeat(65),
    "g".repeat(64),
    ` ${"a".repeat(63)}`,
    "",
  ]) {
    await assert.rejects(complete(ctx(seeded(), body(bad))), (e) => e.code === "bad_sha256");
  }
});

test("uploads/complete stores the hash it was given", async () => {
  const db = seeded();

  const res = await complete(ctx(db, body(SHA)));

  assert.equal(res.status, 200);
  assert.equal(
    db.raw.prepare(`SELECT sha256 FROM product_files WHERE product_id = 'p1'`).get().sha256,
    SHA,
  );
});
