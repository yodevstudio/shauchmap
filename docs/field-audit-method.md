# Field Audit Method

## What it is

A local-only, offline-first tool built into the Android app for structured, tri-state ground inspection of a facility — did the auditor find water, is it free, is it accessible, and so on — designed around a fast (roughly one to two minute) on-site entry flow with a frozen schema, so records stay comparable over time.

## What it is not

Field Audit is **not** the same pipeline as the consumer Evidence system described in [Truth / Evidence / GO](truth-evidence-go.md), and a Field Audit entry does not automatically become production Evidence. It's a separate, local instrument for structured ground-truth collection — useful for understanding data quality at a set of real locations — not a shortcut into the live evidence graph that end users see. Anything from a Field Audit that should inform production Evidence goes through the same review and contribution path any other evidence would.

## Current status

The audit tooling and schema are ready. **Physical field collection has not yet been completed.** This section will be updated once real, on-the-ground data collection actually happens — until then, treat this as a capability the app has, not a body of work that exists yet.

## Why this exists

Most of ShauchMap's toilet records started from an open-data import (see [data-sources.md](data-sources.md)), which is a starting point, not a verification. Structured, repeatable ground inspection is one input toward understanding how much of the map's condition information is trustworthy — and, honestly, toward understanding it well enough to be candid about it, which is the whole point of the Truth/Evidence/GO model in the first place.
