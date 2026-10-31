import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";

import { d1 } from "./d1.mjs";
import * as tsLoader from "./ts-loader.mjs";

registerHooks({ resolve: tsLoader.resolve });
const { refresh } = await import("../src/routes/auth.ts");
const { sha256Hex } = await import("../src/lib/auth.ts");

const SCHEMA = [
  "../migrations/0001_init.sql",
  "../migrations/0002_reward_email_hash_and_file_sha256.sql",
]
  .map((f) => readFileSync(new URL(f, import.meta.url), "utf8"))
  .join("\n");

const TOKEN = "refresh-token-for-s1";

/** One user, one session per id, all in the same token family. */
async function seeded(revokedAt) {
  const db = d1(SCHEMA);
  const expires = new Date(Date.now() + 86_400_000).toISOString();
  db.raw.exec(`INSERT INTO users (id, email, password_hash, display_name, coins, created_at)
               VALUES ('u1', 'u1@test.dev', 'x', '', 0, '2026-01-01T00:00:00.000Z')`);
  const hash = await sha256Hex(TOKEN);
  for (const [id, h] of [["s1", hash], ["s2", await sha256Hex("other")]]) {
    db.raw.prepare(
      `INSERT INTO sessions (id, user_id, refresh_hash, family, user_agent, created_at, expires_at, revoked_at)
       VALUES (?, 'u1', ?, 'family-1', '', ?, ?, ?)`,
    ).run(id, h, new Date().toISOString(), expires, id === "s1" ? revokedAt : null);
  }
  return db;
}

function ctxFor(db) {
  return {
    req: new Request("https://api.test/v1/auth/refresh", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refreshToken: TOKEN }),
    }),
    env: { DB: db, JWT_SECRET: "test-secret" },
    url: new URL("https://api.test/v1/auth/refresh"),
    requestId: "test",
    params: {},
    user: null,
  };
}

const revoked = (db, id) =>
  db.raw.prepare(`SELECT revoked_at FROM sessions WHERE id = ?`).get(id).revoked_at;

test("a fresh refresh token works and revokes only its own session", async () => {
  const db = await seeded(null);

  const res = await refresh(ctxFor(db));
  const body = await res.json();

  assert.equal(res.status, 200);
  assert.ok(body.accessToken);
  assert.ok(revoked(db, "s1"));
  assert.equal(revoked(db, "s2"), null);
});

test("reuse inside the 60s grace window is refused without nuking the family", async () => {
  const db = await seeded(new Date(Date.now() - 5_000).toISOString());

  await assert.rejects(refresh(ctxFor(db)), (e) => e.status === 401);

  assert.equal(revoked(db, "s2"), null); // the other session survives
});

test("reuse outside the grace window revokes the whole family", async () => {
  const db = await seeded(new Date(Date.now() - 10 * 60_000).toISOString());

  await assert.rejects(refresh(ctxFor(db)), (e) => e.status === 401);

  assert.ok(revoked(db, "s2"));
});
