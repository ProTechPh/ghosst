import assert from "node:assert/strict";
import test from "node:test";

import { readJson } from "../src/lib/http.ts";
import { corsHeaders } from "../src/lib/cors.ts";

const encoder = new TextEncoder();

/** A stream body sends no content-length, i.e. what a chunked request looks like. */
function streaming(body) {
  return new Request("https://api.test/", {
    method: "POST",
    body: new ReadableStream({
      start(c) {
        c.enqueue(encoder.encode(body));
        c.close();
      },
    }),
    duplex: "half",
  });
}

test("readJson parses a normal body", async () => {
  const req = new Request("https://api.test/", { method: "POST", body: '{"a":1}' });
  assert.deepEqual(await readJson(req), { a: 1 });
});

test("readJson rejects malformed JSON", async () => {
  const req = new Request("https://api.test/", { method: "POST", body: "{oops" });
  await assert.rejects(readJson(req), (err) => err.status === 400);
});

test("readJson rejects a body that is not a JSON object", async () => {
  for (const body of ["null", "42", '"x"', "[]", "true"]) {
    const req = new Request("https://api.test/", { method: "POST", body });
    await assert.rejects(
      readJson(req),
      (err) => err.status === 400 && err.code === "bad_json",
      body,
    );
  }
});

test("readJson caps a body that declares no content-length", async () => {
  const req = streaming("x".repeat(1_000_001));
  assert.equal(req.headers.get("content-length"), null);
  await assert.rejects(readJson(req), (err) => err.status === 413);
});

test("corsHeaders carries the security headers", () => {
  const h = corsHeaders(new Request("https://api.test/"), {});
  assert.equal(h.get("x-content-type-options"), "nosniff");
  assert.equal(h.get("x-frame-options"), "DENY");
  assert.equal(h.get("strict-transport-security"), "max-age=31536000; includeSubDomains");
  assert.match(h.get("content-security-policy"), /default-src 'none'/);
});
