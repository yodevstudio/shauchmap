// CI-ONLY FIXTURE — not a real Firebase project, not used by any real build.
//
// `lib/firebase_options.dart` is generated per-project by `flutterfire
// configure` and is git-ignored (see .gitignore / SECURITY.md) so that every
// fork points at its own Firebase project rather than a shared one. That
// means `flutter analyze` / `flutter test` have nothing to import unless
// something is present at that path. This fixture is copied there by CI
// (see .github/workflows/ci.yml) purely so the app's source compiles and
// analyzes — every value below is a placeholder string, not a working
// credential, and nothing in this repo's test suite talks to a real backend.
//
// Local development: copy this file to firebase_options.dart as a stopgap,
// or (preferred) run `flutterfire configure` against your own project.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'ci-fixture-not-a-real-key',
    appId: 'ci-fixture-not-a-real-app-id',
    messagingSenderId: '000000000000',
    projectId: 'demo-shauchmap',
    storageBucket: 'demo-shauchmap.appspot.com',
  );
}
