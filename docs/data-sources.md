# Data Sources & Attribution

## Where the toilet locations came from

ShauchMap's production database currently includes roughly 7,741 toilet facility records. Most of these originated as an import from **OpenStreetMap**, the collaborative open geographic database — not from a field survey conducted by ShauchMap itself. That import gave the app a real, useful starting map; it did not, by itself, verify that any individual facility is currently open, clean, or usable. See [Truth / Evidence / GO](truth-evidence-go.md) for how the app handles that gap honestly instead of papering over it.

## License and attribution

OpenStreetMap data is distributed under the **Open Database License (ODbL)**, which requires visible attribution to OpenStreetMap contributors. ShauchMap credits this:

- **In the Android app**, as a small attribution badge near the map.
- **In ShauchMap Instant**, as a footer line on every screen.
- **Here**, explicitly: **Toilet location data includes © OpenStreetMap contributors**, available under the Open Database License. See https://www.openstreetmap.org/copyright for the full attribution and license text.

## What this repository does and doesn't distribute

**The raw imported dataset is not included in this repository.** Only the application code that reads, displays, and lets the community add evidence about toilet records is. This is a size decision as much as a licensing one — the production dataset is tens of megabytes, is kept current independently of the app's release cycle, and republishing a copy of it here would immediately go stale.

## How the data changes since the import

The initial import is a starting point, not a fixed corpus. On top of it, the Android app supports several tightly scoped, individually-owned contribution types tied to the reporting account — condition checks, ratings, votes, check-ins, and reports (see [Truth / Evidence / GO](truth-evidence-go.md)). Of these, only **condition checks** (open / water / usable / lock) carry current-condition authority; ratings and votes are opinion, check-ins are presence/progression bookkeeping, and reports are a moderation channel — none of those carry current-condition authority. **Creating a new top-level toilet record is currently denied server-side for every client**, and the app's own Add-Toilet UX is paused, pending a minimum-supported-version enforcement mechanism — so the facility corpus itself is not currently being extended by the app; the writes it accepts are scoped contributions *about* facilities that already exist. Some community-submitted facility records exist from before top-level creation was disabled; they're treated the same as any other mapped record going forward. Google map *tiles* rendered underneath the Android app's map are a separate thing from the toilet *location data* — the OSM attribution above is about the toilet records, not an implication that the map tiles themselves come from OpenStreetMap.

## Reporting bad data

If you spot an incorrect, duplicate, or outdated toilet record, use the [Toilet data report](https://github.com/YoDevStudio/ShauchMap/issues/new?template=toilet_data.yml) issue template. Please don't include a precise personal location or any other information about yourself in that report beyond what's needed to identify the facility in question — GitHub Issues are public and are not a channel for reporting an urgent, current, in-person facility condition.
