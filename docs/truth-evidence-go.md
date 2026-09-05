# Truth, Evidence, and GO

## The problem with a plain map

A map can show you where a toilet is *listed*. It can't tell you whether that toilet is open right now, has water, is usable, or even still exists. ShauchMap starts from the opposite assumption: **a pin is not a promise.** Being mapped and being currently usable are two different claims, and the app is built to never blur them into one.

## Truth — what's mapped

Truth is a facility's identity and static facts: where it is, what kind of place it is or sits in, who it's for, its fee model, and its structural amenities. Every Truth field is tri-state-aware — `unknown` is a real, first-class value, not a default that gets silently treated as false or as one particular answer:

- A facility whose category is unknown is never presented as "government."
- A facility whose intended users are unknown is never presented as "unisex" by default.
- A facility's fee may genuinely remain **Unknown** rather than being assumed free or paid.
- A record being mapped (sourced from an import) does not by itself establish that the facility currently exists or is usable — that's what Evidence is for.
- A malformed or inconsistent native Truth record fails closed to a defined, conservative fallback rather than guessing at partial data.

Truth deliberately carries no dynamic, moment-to-moment status of its own — folding a live condition into a structural fact is exactly the blur this whole model exists to prevent.

## Evidence — three separate kinds of signal, not one blended score

ShauchMap tracks three distinct kinds of evidence, and they do not average into each other:

**Ratings** — a star rating is one person's opinion at one point in time. Ratings carry **zero current-condition authority** for GO's decision. They inform what a person might expect subjectively; they do not tell GO whether a toilet is open, has water, or is usable right now.

**Votes** — similarly, votes are opinion signals with **zero current-condition authority**. They are not evidence that a facility's condition is what it is right now.

**Condition checks** — this is the only current-condition authority GO uses. Each condition check records a tri-state (`yes` / `no` / `unknown`) observation across four independent dimensions: **open, water, usable, lock**. For each dimension, ShauchMap counts how many recent observations said yes, no, or unknown, and derives a verdict by **strict majority** — a clear yes-majority or no-majority wins; a tie, or no yes/no observations at all, resolves to **Unknown**. These are plain counts, never a confidence percentage.

Condition checks are also **time-bounded**: they're only counted within a **60-minute window**, and the derived verdict has a `valid_until` that expires at the earliest observation's cutoff. Once that time passes, the condition summary is no longer current — it doesn't linger as stale-but-trusted data; it reverts to Unknown/unavailable authority until fresh observations arrive.

Check-ins and reports are moderation and bookkeeping signals, not current-condition authority — they do not, by themselves, make GO "more confident."

## GO — one bounded decision policy over the complete nearby candidate set

GO evaluates the complete set of nearby candidates — every mapped facility within its search radius, in one deterministic pass (same inputs always produce the same result, regardless of input ordering). Strong, corroborated, fresh condition evidence can influence which candidate GO selects over the plain-nearest baseline, within transparent, bounded detour limits — GO will not send you meaningfully out of your way on the strength of evidence unless that evidence clearly earns it. A single, uncorroborated negative condition check is treated as a caution alongside the nearest eligible option, not a veto that removes it from consideration.

**When strong fresh condition evidence isn't available for anywhere nearby, GO falls back to the nearest mapped option — and says so explicitly, with a plain-language reason.** GO never fabricates confidence it doesn't have, and it never expresses its decision as a reliability percentage.

## What this means for you as a user

- A toilet showing **Unknown** for a dimension isn't necessarily missing that quality — it means there isn't a fresh, decisive majority of observations either way.
- A star rating is one person's opinion, not a certified condition check — it will never be the reason GO says a toilet is open, has water, or is usable.
- GO's recommendation reflects the *current, valid* evidence at the moment you ask — when that evidence is strong enough, it can shape the pick; when it isn't, GO falls back to the nearest mapped option and says so. A condition summary that was accurate an hour ago can expire and revert to Unknown without any new condition check ever being recorded.

## Where this lives in the code

The decision logic (Truth parsing, the tri-state Evidence model, and the GO selection algorithm) is implemented once, in [`packages/shauchmap_core`](../packages/shauchmap_core), and consumed by both the Android app and [ShauchMap Instant](instant.md) through a versioned interop layer — so both surfaces make the same decision, the same way, from the same evidence.
