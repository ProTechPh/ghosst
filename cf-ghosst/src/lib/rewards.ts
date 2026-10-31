/**
 * Guards on the AdMob SSV credit path — the only way a balance can go up.
 *
 * The signature proves Google sent the callback, not that *we* earned it:
 * anyone can create their own AdMob account, point that ad unit's SSV URL at
 * this Worker, and be paid for their own ad. The publisher prefix is what
 * separates our inventory from theirs.
 */

/** AdMob publisher id from `lib/services/ad_service.dart` (the app id). */
const PUBLISHER = "ca-app-pub-7791552060229072/";

/**
 * Our two rewarded units, as bare ids. AdMob's SSV callback sends the numeric
 * ad unit id only (`3206073177`), never the `ca-app-pub-…/…` form the SDK uses,
 * so both shapes have to pass or every real reward is rejected.
 */
const OUR_UNITS = new Set(["3206073177", "8242333892"]);

/** Test units live under Google's 3940256099942544 publisher and pay nothing. */
export function isOurRewardedUnit(adUnit: string): boolean {
  // An empty/missing ad_unit is accepted: it is inside the signed payload, so
  // it can only be absent if Google really omitted it — never if it was
  // tampered with. Everything else must be ours.
  return adUnit === "" || adUnit.startsWith(PUBLISHER) || OUR_UNITS.has(adUnit);
}

export interface RewardLimits {
  /** Rewards paid to one account inside `windowMs`. */
  maxPerDay: number;
  /** Minimum spacing between two paid rewards on the same account. */
  gapMs: number;
  windowMs: number;
}

/** 40 ads/day is far past what a person watches; 15s is shorter than any ad. */
export const DEFAULT_LIMITS: RewardLimits = {
  maxPerDay: 40,
  gapMs: 15_000,
  windowMs: 24 * 60 * 60 * 1000,
};

export type RewardVerdict =
  | { ok: true }
  | { ok: false; reason: "daily_cap" | "too_soon" };

/**
 * `state.count` *includes* the callback being judged: the ledger row is written
 * before this read, so two simultaneous callbacks cannot both see room for one.
 */
export function rewardVerdict(
  state: { count: number; lastAt: string | null },
  now: Date,
  limits: RewardLimits = DEFAULT_LIMITS,
): RewardVerdict {
  if (state.count > limits.maxPerDay) return { ok: false, reason: "daily_cap" };

  const last = state.lastAt ? Date.parse(state.lastAt) : NaN;
  if (Number.isFinite(last) && now.getTime() - last < limits.gapMs) {
    return { ok: false, reason: "too_soon" };
  }
  return { ok: true };
}

/** Stable ledger id for a callback with no `transaction_id`. */
export async function contentId(content: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(content),
  );
  const hex = Array.from(new Uint8Array(digest), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  return `q_${hex}`;
}
