/**
 * ShauchMap Evidence V2 — trusted server writer (Cloud Functions, Gen 2).
 *
 * These triggers are the ONLY writer of `toilets/{id}.evidence_v2`. Clients
 * cannot write it: `firestore.rules` denies every update to an existing toilet
 * doc and rejects `evidence_v2` on create (strict allow-list). The Admin SDK
 * bypasses rules.
 *
 * On every raw-evidence write the corresponding section is recomputed from the
 * AUTHORITATIVE current sub-collection contents (never a client delta), inside a
 * transaction. It is written with an EXPLICIT FIELD-PATH update
 * (`evidence_v2.version`, `evidence_v2.<section>`) so sibling sections and
 * `truth_v2` / identity / location are provably untouched.
 *
 * Concurrency: `last_event_at` is the triggering event's own time, parsed to
 * MILLISECONDS. Two CloudEvents in the same millisecond parse equal, so an
 * EQUAL watermark RE-APPLIES (see derive.ts `shouldApplyEvent`). Duplicate /
 * equal apply is safe because every execution recomputes from authoritative
 * state and same-parent transactions serialise + retry.
 *
 * This module derives the trusted ratings, votes, and condition sections of
 * `evidence_v2`. Check-ins and moderation reports intentionally do not feed
 * current-condition evidence. Runtime target: Node 22 (Gen 2).
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { initializeApp } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  FieldPath,
  Timestamp,
  Transaction,
  DocumentReference,
} from "firebase-admin/firestore";

import {
  deriveRatings,
  deriveVotes,
  deriveCondition,
  shouldApplyEvent,
  RawRatingDoc,
  RawVoteDoc,
  RawConditionObs,
} from "./derive";

initializeApp();
const db = getFirestore();

const EVIDENCE_VERSION = 1;
const REGION = "asia-south1";

type Section = "ratings" | "votes" | "condition";

/**
 * Epoch ms of the triggering event's own time. `event.time` is trusted
 * infrastructure metadata; if it is malformed we THROW (which lets the platform
 * retry) rather than invent an ordering timestamp that never existed.
 */
function eventTimeMs(isoTime: string | undefined): number {
  const ms = isoTime == null ? NaN : Date.parse(isoTime);
  if (!Number.isFinite(ms)) {
    throw new Error(`evidence_v2: malformed CloudEvent time: ${String(isoTime)}`);
  }
  return ms;
}

/**
 * Transaction body shared by all three triggers:
 *   1. read the parent; abort if gone.
 *   2. read the stored section watermark; apply only if not strictly older
 *      (`shouldApplyEvent`: equal re-applies).
 *   3. recompute the section from authoritative documents (`compute`).
 *   4. write ONLY `evidence_v2.version` and `evidence_v2.<section>` via explicit
 *      field paths — sibling sections, `truth_v2`, identity and location are
 *      never in the write.
 */
async function updateSection(
  toiletRef: DocumentReference,
  section: Section,
  eventAtMs: number,
  compute: (tx: Transaction) => Promise<Record<string, unknown>>,
): Promise<void> {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(toiletRef);
    if (!snap.exists) return; // parent gone — nothing to summarise

    const stored = snap.get(`evidence_v2.${section}.last_event_at`);
    const storedMs = stored instanceof Timestamp ? stored.toMillis() : null;
    if (!shouldApplyEvent(storedMs, eventAtMs)) return;

    const payload = await compute(tx);
    payload["computed_at"] = FieldValue.serverTimestamp();
    payload["last_event_at"] = Timestamp.fromMillis(eventAtMs);

    tx.update(
      toiletRef,
      new FieldPath("evidence_v2", "version"),
      EVIDENCE_VERSION,
      new FieldPath("evidence_v2", section),
      payload,
    );
  });
}

// --------------------------------------------------------------------- ratings

export const onRatingWrite = onDocumentWritten(
  { region: REGION, document: "toilets/{toiletId}/ratings/{uid}" },
  async (event) => {
    const toiletRef = db.doc(`toilets/${event.params.toiletId}`);
    const eventAtMs = eventTimeMs(event.time);
    await updateSection(toiletRef, "ratings", eventAtMs, async (tx) => {
      const col = await tx.get(toiletRef.collection("ratings"));
      // Pass the RAW `stars` value; deriveRatings decides what is a rating.
      const docs: RawRatingDoc[] = col.docs.map((d) => ({
        stars: d.get("stars"),
      }));
      const { count, average } = deriveRatings(docs);
      return { count, average };
    });
  },
);

// ----------------------------------------------------------------------- votes

export const onVoteWrite = onDocumentWritten(
  { region: REGION, document: "toilets/{toiletId}/votes/{uid}" },
  async (event) => {
    const toiletRef = db.doc(`toilets/${event.params.toiletId}`);
    const eventAtMs = eventTimeMs(event.time);
    await updateSection(toiletRef, "votes", eventAtMs, async (tx) => {
      const col = await tx.get(toiletRef.collection("votes"));
      // Pass the RAW `is_upvote` value; deriveVotes accepts only true/false.
      const docs: RawVoteDoc[] = col.docs.map((d) => ({
        isUpvote: d.get("is_upvote"),
      }));
      const { up, down } = deriveVotes(docs);
      return { up, down };
    });
  },
);

// ------------------------------------------------------------------- condition

export const onConditionWrite = onDocumentWritten(
  { region: REGION, document: "toilets/{toiletId}/condition_checks/{uid}" },
  async (event) => {
    const toiletRef = db.doc(`toilets/${event.params.toiletId}`);
    const eventAtMs = eventTimeMs(event.time);
    await updateSection(toiletRef, "condition", eventAtMs, async (tx) => {
      const col = await tx.get(toiletRef.collection("condition_checks"));
      const nowMs = Date.now();
      // Pass RAW values; deriveCondition validates each observation and drops
      // (does not count) any that is structurally malformed.
      const obs: RawConditionObs[] = col.docs.map((d) => {
        const ts = d.get("timestamp");
        return {
          open: d.get("open"),
          water: d.get("water"),
          usable: d.get("usable"),
          lock: d.get("lock"),
          timestampMs: ts instanceof Timestamp ? ts.toMillis() : NaN,
        };
      });
      const s = deriveCondition(obs, nowMs);
      return {
        open: s.open,
        water: s.water,
        usable: s.usable,
        lock: s.lock,
        contributor_count: s.contributorCount,
        latest_at:
          s.latestAtMs == null ? null : Timestamp.fromMillis(s.latestAtMs),
        valid_until:
          s.validUntilMs == null ? null : Timestamp.fromMillis(s.validUntilMs),
        // Factual per-dimension support counts (yes+no+unknown ==
        // contributor_count for each). Plain counts — never a confidence.
        support: s.support,
      };
    });
  },
);
