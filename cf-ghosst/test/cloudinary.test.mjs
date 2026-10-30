import { test } from "node:test";
import assert from "node:assert/strict";

import { publicIdOf, signParams } from "../src/lib/cloudinary.ts";

const CLOUD = "zp6uwlrj";
const base = `https://res.cloudinary.com/${CLOUD}/image/upload/`;

test("publicIdOf strips the version and the extension", () => {
  assert.equal(
    publicIdOf(`${base}v1759999999/ghosst/abc123.jpg`, CLOUD),
    "ghosst/abc123",
  );
});

test("publicIdOf keeps a folder path with no version", () => {
  assert.equal(publicIdOf(`${base}ghosst/abc123.png`, CLOUD), "ghosst/abc123");
});

test("publicIdOf ignores query strings and transformations", () => {
  assert.equal(
    publicIdOf(`${base}w_400/ghosst/abc123.webp?v=2`, CLOUD),
    "ghosst/abc123",
  );
});

test("publicIdOf rejects anything that is not ours", () => {
  assert.equal(publicIdOf("https://i.imgur.com/x.png", CLOUD), null);
  assert.equal(publicIdOf(`https://example.com/${CLOUD}/a.jpg`, CLOUD), null);
  assert.equal(publicIdOf(`https://res.cloudinary.com/other/image/upload/a.jpg`, CLOUD), null);
  assert.equal(publicIdOf("not a url", CLOUD), null);
});

test("signParams is the sorted params joined with the secret", async () => {
  // sha1("public_id=ghosst/abc&timestamp=1700000000" + "s3cr3t")
  assert.equal(
    await signParams({ timestamp: "1700000000", public_id: "ghosst/abc" }, "s3cr3t"),
    "c0bd6b5b80c4722f5cc44c5bed3b9990dd511167",
  );
});
