<!-- Thanks for contributing to ShauchMap! -->

## What does this PR do?
<!-- A clear, short description. -->

## Related issue
<!-- e.g. Closes #123 -->

## Type of change
- [ ] 🐛 Bug fix
- [ ] ✨ New feature
- [ ] 💄 UI / design
- [ ] 📝 Docs
- [ ] ♻️ Refactor / chore

## Screenshots / recording
<!-- For any UI change, add a before/after. -->

## Checklist
Only check the boxes that actually apply to this PR — a docs-only or backend-only change won't touch most of these.

- [ ] No secrets/keys committed
- [ ] Android: `flutter analyze` is clean, `dart format .` applied, `flutter test` passes
- [ ] Android UI: uses design tokens (`context.sm.*`, `SmText.*`, `SmTokens.*`) — no hardcoded colours/spacing; no `.withOpacity()`, no `BackdropFilter`/blur, no custom-canvas markers
- [ ] Android: did **not** modify the `Toilet` model or its Firestore serialization without updating both adapters
- [ ] Android runtime/UI change: tested on a real device (required for these; not required for docs-only or backend-only changes)
- [ ] Instant: `npm run typecheck && npm run lint && npm test` pass
- [ ] Shared core: `dart analyze && dart test` pass (in `packages/shauchmap_core`)
- [ ] Rules/Functions: relevant suite in `test/rules/` or `functions/` passes
