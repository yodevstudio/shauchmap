# Security Policy

## Reporting a vulnerability

If you discover a security issue, **please do not open a public issue.** Instead, report it privately through GitHub's [security advisories](https://github.com/YoDevStudio/ShauchMap/security/advisories/new) or by contacting the maintainer directly. We'll acknowledge your report as quickly as we can and keep you updated on the fix.

## Secrets & keys — how this project handles them

This repository ships **no** secrets. Anyone building or forking ShauchMap must supply their own.

| Secret | How it's handled |
| :--- | :--- |
| **Google Maps / Places API key** | Injected at build time via `--dart-define=PLACES_API_KEY=…`. Never hardcoded, never committed. |
| **Firebase config** (`firebase_options.dart`, `google-services.json`) | Generated per-project with `flutterfire configure`. Not committed. |
| **Release keystore** (`*.jks`, `key.properties`) | Local only, excluded via `.gitignore`. |
| **`.env`** | Local only, excluded via `.gitignore`. Use `.env.example` as a template. |

## If you fork this project

- Create and restrict **your own** Google Maps/Places key (limit it by package name + SHA-1).
- Set up **your own** Firebase project.
- Generate **your own** release keystore — never reuse another project's signing key.
- Double-check `git status` before your first push; if a secret ever lands in history, rotate it immediately.

## Supported versions

The latest release on the `main` branch receives security updates.
