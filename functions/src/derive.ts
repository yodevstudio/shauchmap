/**
 * ShauchMap Evidence V2 — PURE server-derivation engine.
 *
 * No Firebase, no I/O, no `Date.now()` reads (time is always injected). Every
 * function here recomputes a summary from the AUTHORITATIVE list of raw
 * sub-collection documents — never from a client-supplied delta — and every
 * function is DEFENSIVE: a structurally malformed raw document (from history,
 * an Admin write, a bad import, or a future rules change) is IGNORED, not
 * partially trusted.
 *
 *   - Ratings / votes are OPINION. NOT operational condition, NOT "verified".
 *     0 up + 0 down is NOT "50%". A document without a valid rating is NOT a
 *     rating (it is not counted). A vote value that is not exactly `true` or
 *     `false` is malformed and counts as neither up nor down.
 *   - Condition is derived per dimension from `condition_checks` ONLY, inside a
 *     rolling 60-minute window. A condition document participates only if its
 *     timestamp is finite and open/water/usable (and lock, if present) are each
 *     exactly "yes"/"no"/"unknown". Otherwise the whole observation is dropped
 *     and does NOT count toward `contributorCount`. UNKNOWN never votes.
 *   - Reports and check-ins do NOT feed any of this (see index.ts).
 *   - `validUntilMs` = the EARLIEST (observationTime + window) among the
 *     observations used, so the client can expire the summary once the majority
 *     could have changed by observations simply leaving the window.
 */

export type Tri = "yes" | "no" | "unknown";

export const CONDITION_WINDOW_MS = 60 * 60 * 1000;

/** Raw shapes — fields are `unknown` because the input is untrusted. */
export interface RawRatingDoc {
  stars: unknown;
}
export interface RawVoteDoc {
  isUpvote: unknown;
}
export interface RawConditionObs {
  open: unknown;
  water: unknown;
  usable: unknown;
  lock?: unknown;
  /** epoch ms of the server-authenticated observation time (or non-finite) */
  timestampMs: unknown;
}

/** Validated observation used by the derivation. */
export interface ConditionObs {
  open: Tri;
  water: Tri;
  usable: Tri;
  lock: Tri;
  timestampMs: number;
}

export interface RatingsSummary {
  count: number;
  average: number | null;
}
export interface VotesSummary {
  up: number;
  down: number;
}
/**
 * Factual support counts for ONE condition dimension, over the VALID
 * observations inside the current 60-minute window. Each valid observation
 * contributes exactly one tri-state value per dimension (an absent `lock` is
 * normalised to "unknown"), so `yes + no + unknown == contributorCount` for
 * EVERY dimension. These are plain counts — NOT confidence / probability.
 */
export interface DimensionSupport {
  yes: number;
  no: number;
  unknown: number;
}

export interface ConditionSummary {
  open: Tri;
  water: Tri;
  usable: Tri;
  lock: Tri;
  contributorCount: number;
  latestAtMs: number | null;
  validUntilMs: number | null;
  support: {
    open: DimensionSupport;
    water: DimensionSupport;
    usable: DimensionSupport;
    lock: DimensionSupport;
  };
}

// --------------------------------------------------------------------- helpers

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

/** exact tri-state, or null if not one of the three literals */
function strictTri(v: unknown): Tri | null {
  return v === "yes" || v === "no" || v === "unknown" ? v : null;
}

function verdict(yes: number, no: number): Tri {
  if (yes === 0 && no === 0) return "unknown";
  if (yes > no) return "yes";
  if (no > yes) return "no";
  return "unknown"; // tie
}

// --------------------------------------------------------------------- ratings

/**
 * A document without a valid rating is NOT a rating.
 *   count   = number of docs whose `stars` is an integer 1..5
 *   average = mean of those, or null when there are none
 * Invalid documents are never surfaced (not in count, not in average).
 */
export function deriveRatings(docs: readonly RawRatingDoc[]): RatingsSummary {
  const stars: number[] = [];
  for (const d of docs) {
    const s = d.stars;
    if (typeof s === "number" && Number.isInteger(s) && s >= 1 && s <= 5) {
      stars.push(s);
    }
  }
  const count = stars.length;
  const average =
    count === 0
      ? null
      : Math.round((stars.reduce((a, b) => a + b, 0) / count) * 100) / 100;
  return { count, average };
}

// ----------------------------------------------------------------------- votes

/**
 * Only `isUpvote === true` -> up, `isUpvote === false` -> down. Anything else
 * (missing, null, a string, a number) is malformed and increments NEITHER.
 */
export function deriveVotes(docs: readonly RawVoteDoc[]): VotesSummary {
  let up = 0;
  let down = 0;
  for (const d of docs) {
    if (d.isUpvote === true) up++;
    else if (d.isUpvote === false) down++;
    // else: malformed -> ignored
  }
  return { up, down };
}

// ------------------------------------------------------------------- condition

/**
 * Validate one raw observation. Returns null (drop it) if the timestamp is not
 * finite, or open/water/usable is not an exact tri-state, or `lock` is present
 * but not an exact tri-state. An absent `lock` defaults to "unknown".
 */
export function parseConditionObs(o: RawConditionObs): ConditionObs | null {
  if (!isFiniteNumber(o.timestampMs)) return null;
  const open = strictTri(o.open);
  const water = strictTri(o.water);
  const usable = strictTri(o.usable);
  if (open === null || water === null || usable === null) return null;
  let lock: Tri = "unknown";
  if (o.lock !== undefined && o.lock !== null) {
    const l = strictTri(o.lock);
    if (l === null) return null;
    lock = l;
  }
  return { open, water, usable, lock, timestampMs: o.timestampMs };
}

/**
 * The earliest expiry among the observations used: `min(timestampMs + window)`.
 * Once `now >= validUntil` the OLDEST included observation has left the window,
 * so the majority may already have changed with no document write. Null when no
 * observation was used.
 */
export function computeValidUntil(
  usedTimestampsMs: readonly number[],
  windowMs: number = CONDITION_WINDOW_MS,
): number | null {
  if (usedTimestampsMs.length === 0) return null;
  return Math.min(...usedTimestampsMs.map((t) => t + windowMs));
}

/**
 * Derive the condition summary from raw observations at `nowMs`.
 *   - Each raw observation is validated by `parseConditionObs`; malformed ones
 *     are dropped and do NOT count toward `contributorCount`.
 *   - A (valid) observation participates iff
 *     `nowMs - windowMs <= timestampMs <= nowMs`. A future observation is
 *     defensively excluded.
 *   - Each dimension is independent: strict majority of non-`unknown` votes;
 *     tie or none -> `unknown`.
 *   - `contributorCount` = participating VALID observations. Doc id == uid, so
 *     these are structurally distinct accounts — NOT "verified"/"trusted".
 */
export function deriveCondition(
  raw: readonly RawConditionObs[],
  nowMs: number,
  windowMs: number = CONDITION_WINDOW_MS,
): ConditionSummary {
  const parsed = raw
    .map(parseConditionObs)
    .filter((o): o is ConditionObs => o !== null);

  const used = parsed.filter(
    (o) => o.timestampMs <= nowMs && o.timestampMs >= nowMs - windowMs,
  );

  const zero = (): DimensionSupport => ({ yes: 0, no: 0, unknown: 0 });
  const tally = {
    open: zero(),
    water: zero(),
    usable: zero(),
    lock: zero(),
  };
  for (const o of used) {
    for (const dim of ["open", "water", "usable", "lock"] as const) {
      tally[dim][o[dim]]++; // o[dim] is a validated Tri: 'yes' | 'no' | 'unknown'
    }
  }

  const latestAtMs =
    used.length === 0 ? null : Math.max(...used.map((o) => o.timestampMs));

  return {
    open: verdict(tally.open.yes, tally.open.no),
    water: verdict(tally.water.yes, tally.water.no),
    usable: verdict(tally.usable.yes, tally.usable.no),
    lock: verdict(tally.lock.yes, tally.lock.no),
    contributorCount: used.length,
    latestAtMs,
    validUntilMs: computeValidUntil(
      used.map((o) => o.timestampMs),
      windowMs,
    ),
    support: tally,
  };
}

// ------------------------------------------------------- concurrency guard

/**
 * Should an incoming trigger event apply its recomputation over the stored
 * derived section?
 *
 * `last_event_at` is the triggering event's own time, parsed with
 * `Date.parse()` which resolves only to MILLISECONDS. Two distinct CloudEvents
 * that occur within the same millisecond therefore parse to the SAME value, so
 * an EQUAL watermark MUST re-apply (not skip) — otherwise the second event's
 * data could be lost. This is safe: every execution recomputes from the
 * AUTHORITATIVE current collection contents (not a delta), and Firestore
 * transactions on the same parent document serialise, so a duplicate/equal
 * apply just re-derives the same authoritative answer.
 *
 *   incoming <  stored  -> skip  (a genuinely older, out-of-order event)
 *   incoming == stored  -> apply (same-ms events must not be dropped)
 *   incoming >  stored  -> apply
 *
 * A missing/non-finite `incoming` is a programming error (index.ts throws on a
 * malformed `event.time` rather than inventing one) — throw here too.
 */
export function shouldApplyEvent(
  storedLastEventAtMs: number | null | undefined,
  incomingEventAtMs: number,
): boolean {
  if (!isFiniteNumber(incomingEventAtMs)) {
    throw new Error(
      `shouldApplyEvent: incoming event time is not finite: ${String(incomingEventAtMs)}`,
    );
  }
  if (storedLastEventAtMs == null || !isFiniteNumber(storedLastEventAtMs)) {
    return true;
  }
  return incomingEventAtMs >= storedLastEventAtMs;
}
