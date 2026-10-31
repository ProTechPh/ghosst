import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  contentId,
  isOurRewardedUnit,
  rewardVerdict,
  DEFAULT_LIMITS,
} from "../src/lib/rewards.ts";

const now = new Date("2026-10-30T12:00:00.000Z");
const at = (offsetMs) => new Date(now.getTime() + offsetMs).toISOString();

test("isOurRewardedUnit accepts our two production rewarded units", () => {
  assert.equal(isOurRewardedUnit("ca-app-pub-7791552060229072/3206073177"), true);
  assert.equal(isOurRewardedUnit("ca-app-pub-7791552060229072/8242333892"), true);
});

test("isOurRewardedUnit accepts a callback with no ad_unit (Google omitted it)", () => {
  assert.equal(isOurRewardedUnit(""), true);
});

test("isOurRewardedUnit rejects Google's public test units — they pay nothing", () => {
  assert.equal(isOurRewardedUnit("ca-app-pub-3940256099942544/5224354917"), false);
});

test("isOurRewardedUnit rejects a lookalike publisher", () => {
  assert.equal(isOurRewardedUnit("ca-app-pub-7791552060229072X/123"), false);
  assert.equal(isOurRewardedUnit("ca-app-pub-7791552060229071/123"), false);
});

test("rewardVerdict pays a reward inside the pace limits", () => {
  assert.deepEqual(rewardVerdict({ count: 3, lastAt: at(-60_000) }, now), { ok: true });
});

test("rewardVerdict allows the first reward of an account", () => {
  assert.deepEqual(rewardVerdict({ count: 1, lastAt: null }, now), { ok: true });
});

test("rewardVerdict pays the last slot and the row beyond it", () => {
  assert.deepEqual(
    rewardVerdict({ count: DEFAULT_LIMITS.maxPerDay, lastAt: at(-60_000) }, now),
    { ok: true },
  );
  assert.deepEqual(
    rewardVerdict({ count: DEFAULT_LIMITS.maxPerDay + 1, lastAt: at(-60_000) }, now),
    { ok: false, reason: "daily_cap" },
  );
});

test("rewardVerdict stops two callbacks that arrive back to back", () => {
  assert.deepEqual(
    rewardVerdict({ count: 1, lastAt: at(-1_000) }, now),
    { ok: false, reason: "too_soon" },
  );
});

test("rewardVerdict ignores an unparseable last timestamp", () => {
  assert.deepEqual(rewardVerdict({ count: 1, lastAt: "garbage" }, now), { ok: true });
});

test("contentId is stable per payload and distinct across payloads", async () => {
  const a = await contentId("user_id=u1&timestamp=1");
  const b = await contentId("user_id=u1&timestamp=1");
  const c = await contentId("user_id=u1&timestamp=2");
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^q_[0-9a-f]{64}$/);
});

// The app's ad units and the Worker's publisher prefix must not drift apart:
// a mismatch silently blocks every reward while the suite stays green.
test("the app's production rewarded unit passes the Worker's publisher guard", () => {
  const dart = readFileSync(
    new URL("../../lib/services/ad_service.dart", import.meta.url),
    "utf8",
  );
  const unit = /prodRewarded\s*=\s*'([^']+)'/.exec(dart)?.[1];
  assert.ok(unit, "prodRewarded not found in ad_service.dart");
  assert.equal(isOurRewardedUnit(unit), true, `${unit} is not under rewards.ts's publisher`);
});
