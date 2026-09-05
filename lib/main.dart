// ┌─────────────────────────────────────────────────────────────────────────┐
// │  ShauchMap — शौच Map                                                    │
// │  A pin is not a promise: separates mapped toilets from current          │
// │  condition evidence, and says Unknown when it can't know.               │
// │                                                                         │
// │  Built by @yodevstudio · github.com/yodevstudio                        │
// │  Open-source under MIT. If you're reading this — welcome to the code.  │
// └─────────────────────────────────────────────────────────────────────────┘
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:ui';
import 'firebase_options.dart';
import 'package:home_widget/home_widget.dart';

import 'services/firestore_service.dart';
import 'config/rollout_config.dart';
import 'widgets/evidence_status_label.dart';
import 'services/notification_service.dart';
import 'services/custom_haptics_service.dart';
import 'screens/add_toilet_wizard.dart';
import 'screens/list_screen.dart';
import 'screens/map_screen.dart';
import 'screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/rating_sheet.dart';
import 'screens/onboarding_screen.dart';
import 'utils/map_launcher.dart';
import 'package:workmanager/workmanager.dart';
import 'package:app_links/app_links.dart';
import 'package:collection/collection.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'theme/sm_theme.dart';
import 'theme/sm_tokens.dart';
import 'theme/sm_widgets.dart';
import 'utils/format.dart';
import 'widgets/travel_mode_sheet.dart';
import 'services/app_settings.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    show GoogleMap, CameraPosition, Marker, MarkerId, BitmapDescriptor;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task == "syncNearestLoo") {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        final position = await Geolocator.getLastKnownPosition();
        final now = DateTime.now();
        // location freshness != evidence freshness. An
        // ACTIONABLE nearby widget suggestion needs a position no older than
        // the direct-GO cached-location safety horizon (30 s). Anything staler
        // (or a future timestamp) publishes the non-actionable state. This is
        // SEPARATE from the Evidence V2 60-minute condition window. WorkManager
        // may therefore often clear the widget — honesty beats fake proximity,
        // and a tap always runs a fresh in-app GO. No background-location
        // permission / continuous tracking is added.
        if (position == null ||
            !isGoPositionFresh(
              position.asGeoPos,
              now,
              maxAge: kGoActionableWidgetMaxAge,
            )) {
          await publishGoWidgetUnavailable(
            'Open ShauchMap to refresh nearby suggestions',
          );
          return true;
        }

        final fs = FirestoreService();
        // the COMPLETE current-position-centered 15-km
        // bounded pool (one-shot geo query, deterministically ordered, NO
        // decision cap), never a map/search stream.
        List<Toilet> pool;
        try {
          pool = await fs
              .getGoPool(
                latitude: position.latitude,
                longitude: position.longitude,
                radiusKm: 15.0,
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          await publishGoWidgetUnavailable(
            'Open ShauchMap to refresh nearby suggestions',
          );
          return true;
        }

        // the home widget uses the SAME frozen GO V2 engine as the
        // in-app GO button — no independent nearest-distance ranking here.
        final decision = resolveGo(
          toilets: pool,
          userLat: position.latitude,
          userLng: position.longitude,
          now: now,
        );
        await publishGoWidgetData(decision, now);
      } catch (e) {
        debugPrint("Workmanager error: $e");
        // if we can still write widget state, clear stale
        // actionable ids so an old recommendation does not linger. Narrow
        // nested guard — if HomeWidget itself is what failed, swallow it.
        try {
          await publishGoWidgetUnavailable(
            'Open ShauchMap to refresh nearby suggestions',
          );
        } catch (_) {}
      }
    }
    return true;
  });
}

/// Writes the home-widget SharedPreferences payload from a GO V2 [decision].
///
/// SMALL widget  -> `decision.selected`.
/// MEDIUM widget -> `decision.selected` then `decision.alternatives` in order
/// (never a lower-authority toilet from outside the decision result).
/// `decision.selected == null` -> every stored toilet id/name is CLEARED so a
/// stale widget tap has no navigation target, and a neutral
/// "No confident suggestion" is shown.
///
/// The refresh label says "Suggestion updated ..." — the time the
/// *suggestion* was computed, never a claim that a toilet was verified.
Future<void> publishGoWidgetData(GoDecision decision, DateTime now) async {
  final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
  final ampm = now.hour >= 12 ? 'PM' : 'AM';
  final minute = now.minute.toString().padLeft(2, '0');
  final payload = goWidgetPayload(
    decision,
    updatedLabel: 'Suggestion updated $hour:$minute $ampm',
    now: now,
    formatMeters: formatDistance,
  );
  await _writeWidgetPayload(payload);
}

/// Publish the "no trustworthy suggestion" widget state: EVERY actionable
/// id/name cleared, an honest neutral [message]. / .
Future<void> publishGoWidgetUnavailable(String message) async {
  final now = DateTime.now();
  final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
  final ampm = now.hour >= 12 ? 'PM' : 'AM';
  final minute = now.minute.toString().padLeft(2, '0');
  await _writeWidgetPayload(
    goWidgetUnavailablePayload(
      updatedLabel: 'Suggestion updated $hour:$minute $ampm',
      message: message,
    ),
  );
}

Future<void> _writeWidgetPayload(Map<String, String> payload) async {
  for (final entry in payload.entries) {
    await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
  }
  await HomeWidget.updateWidget(
    name: 'WidgetProvider',
    androidName: 'WidgetProvider',
  );
  await HomeWidget.updateWidget(
    name: 'WidgetProviderMedium',
    androidName: 'WidgetProviderMedium',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();

  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {}

  // Lock screen geometry to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Force transparent immersive status bar overlays
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final GoogleMapsFlutterPlatform mapsImplementation =
      GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    try {
      await mapsImplementation.initializeWithRenderer(
        AndroidMapRenderer.latest,
      );
    } on PlatformException catch (e) {
      debugPrint('Map renderer: $e');
    }
  }

  bool initSuccess = false;

  for (int i = 0; i < 2; i++) {
    try {
      // Initialize Firebase natively on startup using existing firebase_options.dart
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      // Enable Firestore offline persistence with unlimited cache
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // Pass all uncaught "fatal" errors from the framework to Crashlytics
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      initSuccess = true;
      break;
    } catch (e) {
      debugPrint("Firebase initialization failed on attempt ${i + 1}: $e");
      if (i == 0) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (!initSuccess) {
    runApp(const RetryScreen());
    return;
  }

  try {
    Workmanager().initialize(callbackDispatcher);
    Workmanager().registerPeriodicTask(
      "1",
      "syncNearestLoo",
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e) {
    debugPrint("Workmanager init failed: $e");
  }

  await AppSettings.instance.load();
  runApp(const ShauchMapApp());
}

/// One GO V2 alternative row inside the GO preview. It preserves the
/// alternative's own warning / identity state (from `presentGoAlternative`),
/// never re-derives policy, and shows moderation-flagged options never (the
/// engine already excludes them).
class _GoAlternativeRow extends StatelessWidget {
  final GoAlternative alt;
  final Color toneColor;
  final VoidCallback onTap;

  const _GoAlternativeRow({
    required this.alt,
    required this.toneColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final p = presentGoAlternative(alt);
    final (distNum, unit) = formatDistanceParts(alt.distanceMeters);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SmTokens.rSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SmTokens.s8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: toneColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: SmTokens.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alt.toilet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SmText.body.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (p.cautions.isEmpty)
                    Text(
                      p.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmText.caption.copyWith(color: c.ink3),
                    )
                  else
                    // EVERY structured caution from
                    // presentGoAlternative is rendered before a non-confirming
                    // alternative tap (identity + unavailable + water + lock) —
                    // no arbitrary truncation. Compact + wrapping.
                    for (final line in p.cautions)
                      Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SmText.caption.copyWith(color: c.ink3),
                      ),
                ],
              ),
            ),
            const SizedBox(width: SmTokens.s8),
            Text(
              '$distNum$unit',
              style: SmText.caption.copyWith(color: c.ink2),
            ),
            if (alt.requiresConfirmation)
              Padding(
                padding: const EdgeInsets.only(left: SmTokens.s4),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: c.ink3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RetryScreen extends StatelessWidget {
  const RetryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SmColors.dark],
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
          bodyMedium: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w400,
            color: Colors.white,
          ),
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.sm.bg,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48.0, color: context.sm.ink3),
                const SizedBox(height: 16.0),
                Text(
                  "Connection Error",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8.0),
                Text(
                  "Could not connect to servers.\nPlease check your network and try again.",
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: context.sm.ink2),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  onPressed: () => main(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.sm.brandSolid,
                    foregroundColor: context.sm.onBrand,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 12.0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text(
                    "Retry",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppSnackBar(
  String message, {
  Color? backgroundColor,
  bool isError = false,
}) {
  rootScaffoldMessengerKey.currentState?.clearSnackBars();
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message, style: SmText.body.copyWith(color: Colors.white)),
      backgroundColor:
          backgroundColor ??
          (isError ? SmColors.light.statusClosed : SmColors.dark.brandSolid),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(
        bottom: kBottomNavigationBarHeight + 12.0,
        left: 16.0,
        right: 16.0,
      ),
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
    ),
  );
}

class ShauchMapApp extends StatelessWidget {
  const ShauchMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.instance.themeMode,
      builder: (context, mode, child) => MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        title: 'ShauchMap',
        debugShowCheckedModeBanner: false,
        theme: SmTheme.light(),
        darkTheme: SmTheme.dark(),
        themeMode: mode,
        builder: (context, child) => child == null
            ? const SizedBox.shrink()
            : SmTheme.clampTextScale(context, child),
        home: FutureBuilder<bool>(
          future: SharedPreferences.getInstance().then(
            (p) => p.getBool('onboarding_done') ?? false,
          ),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(
                backgroundColor: Colors.black,
                body: SizedBox.shrink(),
              );
            }
            if (snap.data == true) return const NavigationShell();
            return OnboardingScreen(
              onDone: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const NavigationShell()),
              ),
              onEmergency: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const NavigationShell()),
              ),
            );
          },
        ),
      ),
    );
  }
}

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell>
    with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  int _selectedTabIndex = 0; // 0: Map, 1: You

  StreamSubscription<List<Toilet>>? _toiletsSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Position>? _positionSubscription;
  List<Toilet> _toilets = [];
  double? _userLat;
  double? _userLng;
  String? _viewingPlaceName;
  double? _viewingLat;
  double? _viewingLng;
  Position? _userPosition;

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  // Simulated login states
  bool _isSignedIn = false;
  String? _userId;
  String? _userName;
  VoidCallback? _onSignInSuccess;

  // guard so the public-profile mirror runs at most ONCE per
  // uid per app session, no matter how many auth-state callbacks arrive.
  // Reset on sign-out (and on a mirror failure, to allow a retry next event).
  String? _publicProfileEnsuredUid;

  // Streak
  int _streakCount = 0;

  // Connectivity
  bool _isOnline = true;

  Future<void> _initConnectivity() async {
    final initial = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = initial.any((r) => r != ConnectivityResult.none);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _setupAuth();
    if (_userId != null) _refreshStreak();
    _initConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> result,
    ) {
      if (mounted) {
        setState(() {
          _isOnline = result.any((r) => r != ConnectivityResult.none);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      _checkPendingReview();
    });
    WidgetsBinding.instance.addObserver(this);

    HomeWidget.setAppGroupId('com.shauchmap.app');
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link if app was cold-started from a deep link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint("Failed to get initial deep link: $e");
    }

    // Handle deep links while app is running or in background
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint("Deep link stream error: $err");
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateWidgetWithNearestToilet();
      _checkPendingReview();
      NotificationService().resetReengagementNudge();
    }
  }

  Future<void> _checkPendingReview() async {
    final prefs = await SharedPreferences.getInstance();
    final eligibleTimeMs = prefs.getInt('pending_review_eligible_time');
    final toiletId = prefs.getString('pending_review_toilet_id');
    final toiletName = prefs.getString('pending_review_toilet_name');

    if (eligibleTimeMs == null || toiletId == null || toiletName == null) {
      return;
    }

    final eligibleTime = DateTime.fromMillisecondsSinceEpoch(eligibleTimeMs);
    final now = DateTime.now();

    if (now.isAfter(eligibleTime)) {
      if (now.difference(eligibleTime).inHours > 12) {
        await prefs.remove('pending_review_eligible_time');
        await prefs.remove('pending_review_toilet_id');
        await prefs.remove('pending_review_toilet_name');
        return;
      }

      if (!mounted) {
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final dc = dialogContext.sm;
          return AlertDialog(
            backgroundColor: dc.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SmTokens.rCard),
              side: BorderSide(color: dc.line),
            ),
            title: Text(
              "You're back",
              style: SmText.subhead.copyWith(
                color: dc.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              'Did you visit $toiletName? A quick rating helps the next person.',
              style: SmText.body.copyWith(color: dc.ink2),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await prefs.remove('pending_review_eligible_time');
                  await prefs.remove('pending_review_toilet_id');
                  await prefs.remove('pending_review_toilet_name');
                  await NotificationService().cancelRateVisitNudge();
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: Text("Not now", style: TextStyle(color: dc.ink3)),
              ),
              TextButton(
                onPressed: () async {
                  await prefs.remove('pending_review_eligible_time');
                  await prefs.remove('pending_review_toilet_id');
                  await prefs.remove('pending_review_toilet_name');
                  await NotificationService().cancelRateVisitNudge();
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();

                  if (mounted) {
                    Toilet? targetToilet;
                    try {
                      targetToilet = _toilets.firstWhereOrNull(
                        (t) => t.id == toiletId,
                      );
                    } catch (_) {}
                    if (targetToilet == null) {
                      try {
                        final doc = await FirebaseFirestore.instance
                            .collection('toilets')
                            .doc(toiletId)
                            .get();
                        if (doc.exists) {
                          targetToilet = toiletFromFirestore(doc);
                        }
                      } catch (_) {}
                    }

                    if (targetToilet != null && mounted) {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (sheetContext) => RatingSheet(
                          toilet: targetToilet!,
                          userId: _userId,
                          userName: _userName,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  "Rate it",
                  style: TextStyle(
                    color: dc.brand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'shauchmap') return;

    // BOTH the emergency deep link and a widget/`navigate` deep
    // link open the app and run a FRESH GO V2 resolution. A stored widget
    // toilet id is a hint/context only — never authority to Map-launch a
    // cached recommendation that may now be stale.
    if (uri.host == 'emergency') {
      _startEmergencyFlow();
    } else if (uri.host == 'navigate') {
      _startEmergencyFlow(hintToiletId: uri.queryParameters['toiletId']);
    }
  }

  bool _isEmergencyDialogShowing = false;
  bool _isNavigatingFlowActive = false;

  void _showEmergencyDialog() {
    if (_isEmergencyDialogShowing || !mounted) return;
    _isEmergencyDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: ctx.sm.ink.withValues(alpha: 0.45),
          body: Center(
            child: SmCard(
              padding: const EdgeInsets.all(SmTokens.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: ctx.sm.brandSolid,
                    strokeWidth: 2.5,
                  ),
                  const SizedBox(height: SmTokens.s16),
                  Text(
                    'Finding a nearby option…',
                    style: SmText.body.copyWith(color: ctx.sm.ink),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) {
      _isEmergencyDialogShowing = false;
    });
  }

  void _dismissEmergencyDialog() {
    if (_isEmergencyDialogShowing && mounted) {
      _isEmergencyDialogShowing = false;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  // ==========================================================================
  // GO V2 LIVE RESOLUTION + PREVIEW
  //
  // Every GO surface funnels through resolveGo(...) -> the frozen decideGo. The
  // UI below only FORMATS a GoDecision (via go_presentation.dart); it never
  // re-ranks. Legacy is_open / ratings / votes / star averages never touch it.
  // ==========================================================================

  Color _toneColor(BuildContext ctx, GoTone tone) => switch (tone) {
    GoTone.positive => ctx.sm.statusOpen,
    GoTone.warning => ctx.sm.statusUnsure,
    GoTone.neutral => ctx.sm.ink3,
  };

  double _toneMarkerHue(GoTone tone) => switch (tone) {
    // Green ONLY for a corroborated-positive selection; otherwise a NEUTRAL
    // violet pin, or an orange warning pin. Never universal green.
    GoTone.positive => BitmapDescriptor.hueGreen,
    GoTone.warning => BitmapDescriptor.hueOrange,
    GoTone.neutral => BitmapDescriptor.hueViolet,
  };

  DateTime? _lastGoWidgetRefresh;

  /// Acquire an acceptable CURRENT position for GO. SELF-SUFFICIENT — it
  /// does its own permission / service gate and never assumes
  /// `_initLocation()` ran first. Returns null rather than ever handing back
  /// an arbitrarily stale fix: an unknown current location is safer than a
  /// confident recommendation for the wrong city. A valid fresh / last-known
  /// fix also refreshes `_userPosition`.
  ///
  /// Each freshness decision reads its OWN `DateTime.now()`.
  /// The permission prompt can hold the user for a long time, so a single
  /// captured `now` would let a last-known fix (or even a delayed
  /// `getCurrentPosition` result) pass its age check against a stale clock.
  Future<Position?> _acquireGoPosition() async {
    // A recently-held fix is enough — no permission round-trip needed.
    final cached = _userPosition;
    if (cached != null &&
        isGoPositionFresh(
          cached.asGeoPos,
          DateTime.now(),
          maxAge: kGoCachedPositionMaxAge,
        )) {
      return cached;
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          isGoPositionFresh(
            lastKnown.asGeoPos,
            DateTime.now(),
            maxAge: kGoLastKnownMaxAge,
          )) {
        _userPosition = lastKnown;
        return lastKnown;
      }

      _showEmergencyDialog();
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
        // Even a "current" fix is validated against a FRESH clock — the GO
        // trust boundary does not assume the platform returns something
        // instantaneous. Must be <= the cached-position horizon (10 s).
        if (!isGoPositionFresh(
          position.asGeoPos,
          DateTime.now(),
          maxAge: kGoCachedPositionMaxAge,
        )) {
          return null;
        }
        _userPosition = position;
        return position;
      } finally {
        _dismissEmergencyDialog();
      }
    } catch (_) {
      // Permission / service / platform / timeout errors — no stale
      // fallback. The caller shows the honest 'cannot locate' path.
      _dismissEmergencyDialog();
      return null;
    }
  }

  /// Load the COMPLETE 15-km bounded GO candidate pool centered on [position] —
  /// NEVER the map viewport, search destination, `_viewingLat/_viewingLng`, or
  /// the stale map stream, and NO pre-engine decision cap. Returns
  /// null on failure; the caller must NOT fall back to `_toilets`.
  Future<List<Toilet>?> _loadGoPoolAt(GeoPos position) async {
    try {
      return await _firestoreService
          .getGoPool(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: 15.0,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// the GO core is platform-free. Acquire a geolocator `Position`
  /// (also used by the map/widget) then hand GO a plain `GeoPos`.
  Future<GeoPos?> _acquireGoPos() async =>
      (await _acquireGoPosition())?.asGeoPos;

  /// Resolve against an EXPLICIT current-user pool + position. Returns a
  /// GoResolutionSnapshot carrying the exact position used, the decision,
  /// and the `now` it was resolved at .
  GoResolutionSnapshot _resolveGoFor(List<Toilet> pool, GeoPos pos) {
    final now = DateTime.now();
    return (
      position: pos,
      decision: resolveGo(
        toilets: pool,
        userLat: pos.latitude,
        userLng: pos.longitude,
        now: now,
      ),
      now: now,
    );
  }

  /// Route a fresh GoDecision to the right surface. [hintToiletId] (from a
  /// widget/deep-link tap) is a HINT only: it is honoured ONLY when it
  /// resolves to a NON-selected alternative in the FRESH active tier; a hint
  /// that is the fresh selected, or is absent / flagged / dropped, falls
  /// through to the normal selected preview. Identity authority /
  /// confirmation / warnings / moderation / revalidation are never bypassed.
  Future<void> _presentGoResult(
    GoResolutionSnapshot snapshot, {
    String? hintToiletId,
  }) async {
    if (!mounted) return;
    final decision = snapshot.decision;
    if (decision.selected == null) {
      final action = await _showGoNullSheet(decision);
      if (action == GoNullAction.retry) {
        await _startEmergencyFlow();
      } else if (action == GoNullAction.browse && mounted) {
        setState(() => _selectedTabIndex = 0);
      }
      return;
    }
    final focus = resolveHintFocus(decision, hintToiletId, now: snapshot.now);
    await _showGoPreviewSheet(snapshot, focus: focus);
  }

  // ---- travel-mode + Maps launch (shared) --------------------------------
  Future<void> _launchGoNavigation(Toilet toilet, double distMeters) async {
    if (!mounted) return;
    final selectedMode = await showTravelModeSheet(
      context,
      distanceMeters: distMeters,
    );
    if (selectedMode == null || !mounted) return;
    final etaSeconds = selectedMode == TravelMode.driving
        ? (distMeters / 11.1).round()
        : selectedMode == TravelMode.bicycling
        ? (distMeters / 4.1).round()
        : (distMeters / 1.4).round();
    await MapLauncher.launch(
      destination: LatLng(toilet.latitude, toilet.longitude),
      toiletName: toilet.name,
      toiletId: toilet.id,
      etaSeconds: etaSeconds,
      mode: selectedMode,
    );
  }

  /// navigation-time revalidation. A GO decision is a time-dependent
  /// snapshot; evidence / moderation can expire while the preview is open.
  ///
  /// PRIMARY: if the fresh selected id is unchanged and the confirmation
  /// contract is not materially stronger, navigate to the FRESH result.
  /// Otherwise refresh the preview and tell the user.
  ///
  /// ALTERNATIVE ([alternativeId] set): the chosen toilet must still be in the
  /// fresh decision's active tier (selected or alternatives); else refresh.
  Future<void> _revalidateAndNavigate(
    GoResolutionSnapshot stale, {
    String? alternativeId,
  }) async {
    if (!mounted) return;
    // Revalidation builds a completely NEW snapshot: reacquired current
    // position + freshly-loaded current-user GO pool. Never `_toilets` /
    // a search pool.
    final pos = await _acquireGoPos();
    if (pos == null) {
      if (mounted) {
        showAppSnackBar(
          'Cannot confirm your location right now',
          isError: true,
        );
      }
      return;
    }
    final pool = await _loadGoPoolAt(pos);
    if (pool == null) {
      if (mounted) {
        showAppSnackBar(
          "Couldn't refresh nearby toilets. Try again.",
          isError: true,
        );
      }
      return;
    }
    final r = _resolveGoFor(pool, pos);
    final fresh = r.decision;
    final String? wantId = alternativeId ?? fresh.selected?.id;

    // ONE decision point. Confirmation (if any) happens here,
    // once, on FRESH metadata — the preview's primary CTA does NOT pre-confirm.
    switch (goRevalidationOutcome(stale, r, targetId: alternativeId)) {
      case GoRevalidationOutcome.refreshSuggestion:
        if (mounted) {
          showAppSnackBar(
            'Nearby evidence changed. GO refreshed your suggestion.',
          );
        }
        await _presentGoResult(r);
        return;

      case GoRevalidationOutcome.refreshOption:
        if (mounted) {
          showAppSnackBar('Nearby evidence changed. GO refreshed this option.');
        }
        final freshTarget = wantId == null
            ? null
            : findInActiveTier(fresh, wantId, now: r.now);
        await _showGoPreviewSheet(
          r,
          focus: (alternativeId != null) ? freshTarget : null,
        );
        return;

      case GoRevalidationOutcome.confirmThenLaunch:
        final freshTarget = findInActiveTier(fresh, wantId!, now: r.now)!;
        final ok = await _confirmGoNavigation(
          presentGoAlternative(goAlternativeFromTarget(freshTarget)),
          freshTarget.toilet,
          freshTarget.distanceMeters,
        );
        if (ok != true || !mounted) return;
        await _launchGoNavigation(
          freshTarget.toilet,
          freshTarget.distanceMeters,
        );
        return;

      case GoRevalidationOutcome.launch:
        final freshTarget = findInActiveTier(fresh, wantId!, now: r.now)!;
        await _launchGoNavigation(
          freshTarget.toilet,
          freshTarget.distanceMeters,
        );
        return;
    }
  }

  /// Confirmation sheet shown BEFORE MapLauncher whenever requiresConfirmation.
  /// The warning/cautions appear ABOVE the primary action. Returns true only on
  /// an explicit "Navigate anyway" tap.
  Future<bool?> _confirmGoNavigation(
    GoPresentation p,
    Toilet toilet,
    double distMeters,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final c = sheetCtx.sm;
        return Container(
          decoration: smSheetDecoration(sheetCtx),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SmTokens.s20,
                SmTokens.s8,
                SmTokens.s20,
                SmTokens.s24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SmGrabHandle()),
                  const SizedBox(height: SmTokens.s12),
                  SmEyebrow(p.headline.toUpperCase()),
                  const SizedBox(height: SmTokens.s8),
                  Text(
                    toilet.name,
                    style: SmText.subhead.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: SmTokens.s8),
                  Text(
                    p.explanation,
                    style: SmText.body.copyWith(color: c.ink2),
                  ),
                  if (p.cautions.isNotEmpty) ...[
                    const SizedBox(height: SmTokens.s12),
                    for (final line in p.cautions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SmTokens.s4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: _toneColor(sheetCtx, GoTone.warning),
                            ),
                            const SizedBox(width: SmTokens.s8),
                            Expanded(
                              child: Text(
                                line,
                                style: SmText.caption.copyWith(color: c.ink2),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: SmTokens.s16),
                  SmPrimaryButton(
                    label: p.primaryCta ?? 'Navigate anyway',
                    icon: Icons.near_me_rounded,
                    onTap: () => Navigator.of(sheetCtx).pop(true),
                  ),
                  const SizedBox(height: SmTokens.s8),
                  TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(false),
                    child: Text(
                      p.secondaryCta ?? 'Choose another option',
                      style: SmText.body.copyWith(color: c.ink2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Null-result sheet: NO Navigate action. The engine deliberately returned
  /// no selection, so GO must not silently pick a nearest-by-distance record.
  /// Returns the user's chosen action AFTER the sheet closes, so the caller
  /// can fully release the active flow before starting a new resolution
  /// .
  Future<GoNullAction> _showGoNullSheet(GoDecision decision) async {
    final p = presentGoDecision(decision);
    if (!mounted) return GoNullAction.dismiss;
    final result = await showModalBottomSheet<GoNullAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final c = sheetCtx.sm;
        return Container(
          decoration: smSheetDecoration(sheetCtx),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SmTokens.s20,
                SmTokens.s8,
                SmTokens.s20,
                SmTokens.s24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SmGrabHandle()),
                  const SizedBox(height: SmTokens.s12),
                  SmEyebrow(p.headline.toUpperCase()),
                  const SizedBox(height: SmTokens.s8),
                  Text(
                    p.explanation,
                    style: SmText.body.copyWith(color: c.ink2),
                  ),
                  for (final line in p.cautions)
                    Padding(
                      padding: const EdgeInsets.only(top: SmTokens.s8),
                      child: Text(
                        line,
                        style: SmText.caption.copyWith(color: c.ink3),
                      ),
                    ),
                  const SizedBox(height: SmTokens.s16),
                  SmPrimaryButton(
                    label: p.secondaryCta == 'Retry' ? 'Retry' : 'Browse map',
                    icon: p.secondaryCta == 'Retry'
                        ? Icons.refresh_rounded
                        : Icons.map_rounded,
                    onTap: () => Navigator.of(sheetCtx).pop(
                      p.secondaryCta == 'Retry'
                          ? GoNullAction.retry
                          : GoNullAction.browse,
                    ),
                  ),
                  if (p.secondaryCta == 'Retry') ...[
                    const SizedBox(height: SmTokens.s8),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(sheetCtx).pop(GoNullAction.browse),
                      child: Text(
                        'Browse map',
                        style: SmText.body.copyWith(color: c.ink2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? GoNullAction.dismiss;
  }

  /// [focus] set => the sheet is centred on a widget/deep-link HINT target
  /// (a fresh non-selected alternative) instead of `decision.selected`.
  /// Copy/tone/confirmation come from the focus target's REAL authority +
  /// condition .
  Future<void> _showGoPreviewSheet(
    GoResolutionSnapshot snapshot, {
    GoTarget? focus,
  }) async {
    final decision = snapshot.decision;
    final toilet = focus?.toilet ?? decision.selected!;
    final distMeters =
        focus?.distanceMeters ?? decision.selectedDistanceMeters ?? 0;
    final GoPresentation p = focus != null
        ? presentGoAlternative(goAlternativeFromTarget(focus))
        : presentGoDecision(
            decision,
            selectedIdentity: decision.selected!.truth.identityStatus,
          );
    final altList = decision.alternatives
        .where((a) => a.toilet.id != focus?.toilet.id)
        .toList();
    // the origin is the EXACT position this decision was
    // resolved from — never a later mutation of `_userPosition`.
    final userLatLng = LatLng(
      snapshot.position.latitude,
      snapshot.position.longitude,
    );
    final toiletLatLng = LatLng(toilet.latitude, toilet.longitude);
    final midPoint = LatLng(
      (userLatLng.latitude + toiletLatLng.latitude) / 2,
      (userLatLng.longitude + toiletLatLng.longitude) / 2,
    );

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final c = sheetCtx.sm;
        final toneColor = _toneColor(sheetCtx, p.tone);
        return Container(
          decoration: smSheetDecoration(sheetCtx),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SmTokens.s20,
                  SmTokens.s8,
                  SmTokens.s20,
                  SmTokens.s24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: SmGrabHandle()),
                    const SizedBox(height: SmTokens.s12),
                    SmEyebrow(p.headline.toUpperCase()),
                    const SizedBox(height: SmTokens.s12),
                    // Mini-map: a STRAIGHT-LINE context view. No polyline (that
                    // would imply a calculated walking route). Selected marker
                    // is neutral unless corroborated-positive evidence backs it.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(SmTokens.rCard),
                      child: SizedBox(
                        height: 140,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: midPoint,
                            zoom: 14.5,
                          ),
                          liteModeEnabled: true,
                          zoomGesturesEnabled: false,
                          scrollGesturesEnabled: false,
                          rotateGesturesEnabled: false,
                          tiltGesturesEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          markers: {
                            Marker(
                              markerId: const MarkerId('user'),
                              position: userLatLng,
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueAzure,
                              ),
                            ),
                            Marker(
                              markerId: const MarkerId('toilet'),
                              position: toiletLatLng,
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                _toneMarkerHue(p.tone),
                              ),
                            ),
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: SmTokens.s16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (_) {
                            final (goNum, goUnit) = formatDistanceParts(
                              distMeters,
                            );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  goNum,
                                  style: SmText.hero.copyWith(
                                    color: c.ink,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    goUnit,
                                    style: SmText.subhead.copyWith(
                                      color: c.ink2,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: SmTokens.s16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                toilet.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: SmText.subhead.copyWith(
                                  color: c.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: SmTokens.s4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  EvidenceStatusLabel(toilet),
                                  const SizedBox(width: SmTokens.s8),
                                  Text(
                                    'straight-line',
                                    style: SmText.caption.copyWith(
                                      color: c.ink3,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SmTokens.s12),
                    // WHY this option (from the frozen engine, no re-ranking).
                    Container(
                      padding: const EdgeInsets.all(SmTokens.s12),
                      decoration: BoxDecoration(
                        color: toneColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(SmTokens.rSmall),
                      ),
                      child: Text(
                        p.explanation,
                        style: SmText.caption.copyWith(color: c.ink2),
                      ),
                    ),
                    for (final line in p.cautions)
                      Padding(
                        padding: const EdgeInsets.only(top: SmTokens.s8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: _toneColor(sheetCtx, GoTone.warning),
                            ),
                            const SizedBox(width: SmTokens.s8),
                            Expanded(
                              child: Text(
                                line,
                                style: SmText.caption.copyWith(color: c.ink2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: SmTokens.s16),
                    SmPrimaryButton(
                      label: p.primaryCta ?? 'Navigate in Maps',
                      icon: Icons.near_me_rounded,
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        if (!mounted) return;
                        // NO pre-confirmation on stale metadata.
                        // Revalidation is the single decision point — it shows
                        // the one confirmation (on FRESH metadata) if needed.
                        await _revalidateAndNavigate(
                          snapshot,
                          alternativeId: (focus != null && !focus.isSelected)
                              ? focus.toilet.id
                              : null,
                        );
                      },
                    ),
                    if (focus != null) ...[
                      const SizedBox(height: SmTokens.s8),
                      TextButton(
                        onPressed: () async {
                          Navigator.of(sheetCtx).pop();
                          if (!mounted) return;
                          await _showGoPreviewSheet(snapshot);
                        },
                        child: Text(
                          "GO's top pick: ${decision.selected!.name}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SmText.caption.copyWith(color: c.ink2),
                        ),
                      ),
                    ],
                    if (altList.isNotEmpty) ...[
                      const SizedBox(height: SmTokens.s16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SmEyebrow('OTHER NEARBY GO OPTIONS'),
                      ),
                      const SizedBox(height: SmTokens.s8),
                      for (final alt in altList)
                        _GoAlternativeRow(
                          alt: alt,
                          toneColor: _toneColor(
                            sheetCtx,
                            presentGoAlternative(alt).tone,
                          ),
                          onTap: () async {
                            Navigator.of(sheetCtx).pop();
                            if (!mounted) return;
                            await _revalidateAndNavigate(
                              snapshot,
                              alternativeId: alt.toilet.id,
                            );
                          },
                        ),
                    ],
                    const SizedBox(height: SmTokens.s12),
                    GestureDetector(
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        if (!mounted) return;
                        await _showBrowseAllToilets();
                      },
                      child: Text.rich(
                        TextSpan(
                          text: 'Looking for something specific?  ',
                          style: SmText.caption.copyWith(color: c.ink3),
                          children: [
                            TextSpan(
                              text: 'Browse all toilets ↑',
                              style: SmText.caption.copyWith(
                                color: c.brand,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBrowseAllToilets() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SmTokens.rSheet),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: context.sm.surface,
              border: Border.all(color: context.sm.line, width: 1),
            ),
            child: Column(
              children: [
                const SmGrabHandle(),
                Expanded(
                  child: ListScreen(
                    toilets: _toilets,
                    firestoreService: _firestoreService,
                    isSignedIn: _isSignedIn,
                    userId: _userId,
                    userName: _userName,
                    onSignInRequest: () => _triggerSignInGating(() {}),
                    onRefreshToilets: () => setState(() {}),
                    userPosition: _userPosition,
                    searchMode: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startAddToiletFlow() {
    // rollout gate: native Truth V2 creation is paused in this release
    // (see RolloutConfig.addToiletEnabled). Honest UX only — the server
    // rules are the actual enforcement.
    if (!RolloutConfig.addToiletEnabled) {
      showAppSnackBar(RolloutConfig.addToiletPausedMessage);
      return;
    }
    if (!_isSignedIn || _userId == null) {
      _triggerSignInGating(() {});
      return;
    }
    CustomHapticsService.playRewardCrescendo();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddToiletWizard(
          firestoreService: _firestoreService,
          userId: _userId!,
          onRefreshToilets: () => setState(() {}),
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _startEmergencyFlow({String? hintToiletId}) async {
    // The guard blocks SIMULTANEOUS duplicate flows (e.g. a double GO tap).
    // Retry from the no-suggestion sheet loops WITHIN this guarded region;
    // it is not a re-entrant call.
    if (_isNavigatingFlowActive) return;
    _isNavigatingFlowActive = true;
    bool retried = false;
    GoResolutionSnapshot? preview;
    try {
      preview = await runGoFlowLoop(
        acquire: _acquireGoPos,
        loadPool: (pos) async {
          final pool = await _loadGoPoolAt(pos);
          _dismissEmergencyDialog();
          return pool;
        },
        resolve: _resolveGoFor,
        showNull: (d) async {
          final a = await _showGoNullSheet(d);
          if (a == GoNullAction.retry) retried = true;
          if (a == GoNullAction.browse && mounted) {
            setState(() => _selectedTabIndex = 0);
          }
          return a;
        },
        onError: (m) {
          if (mounted) showAppSnackBar(m, isError: true);
        },
      );
    } finally {
      _isNavigatingFlowActive = false;
      _dismissEmergencyDialog();
    }
    // Guard released: the preview's own revalidation / retry can now start a
    // fresh guarded flow. A stale hint is never carried across a retry.
    if (preview != null && mounted) {
      await _presentGoResult(
        preview,
        hintToiletId: retried ? null : hintToiletId,
      );
    }
  }

  void _updateWidgetWithNearestToilet() => unawaited(_refreshGoWidget());

  /// Foreground home-widget refresh. Uses a CURRENT-USER-centered bounded GO
  /// pool (never `_toilets` / a search pool), throttled to avoid a geo query
  /// on every map stream tick. A missing / stale position or an empty pool
  /// publishes the honest no-suggestion state and CLEARS every stale id
  /// .
  Future<void> _refreshGoWidget({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastGoWidgetRefresh != null &&
        now.difference(_lastGoWidgetRefresh!) < const Duration(seconds: 60)) {
      return;
    }
    _lastGoWidgetRefresh = now;

    // an ACTIONABLE widget suggestion needs a position no
    // older than 30 s (kGoActionableWidgetMaxAge) — NOT the 60-minute
    // Evidence V2 condition window. Otherwise clear every actionable id.
    final pos = _userPosition?.asGeoPos;
    if (pos == null ||
        !isGoPositionFresh(pos, now, maxAge: kGoActionableWidgetMaxAge)) {
      await publishGoWidgetUnavailable('Open ShauchMap to refresh');
      return;
    }
    final pool = await _loadGoPoolAt(pos);
    if (pool == null || pool.isEmpty) {
      await publishGoWidgetUnavailable('Open ShauchMap to refresh');
      return;
    }
    final r = _resolveGoFor(pool, pos);
    await publishGoWidgetData(r.decision, r.now);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _toiletsSubscription?.cancel();
    _authSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _updateToiletStream() {
    final double? targetLat = _viewingLat ?? _userLat;
    final double? targetLng = _viewingLng ?? _userLng;

    if (targetLat != null && targetLng != null) {
      _toiletsSubscription?.cancel();
      _toilets.clear();
      if (mounted) setState(() {});

      _toiletsSubscription = _firestoreService
          .getToiletsNearby(
            latitude: targetLat,
            longitude: targetLng,
            radiusKm: 15.0,
          )
          .listen((toilets) {
            if (mounted) {
              setState(() => _toilets = toilets);
              _updateWidgetWithNearestToilet();
            }
          });
    } else {
      _startToiletStreamWithDefaultLocation();
    }
  }

  void _onSearchLocationUpdate(String placeName, double lat, double lng) {
    setState(() {
      _viewingPlaceName = placeName;
      _viewingLat = lat;
      _viewingLng = lng;
    });
    _updateToiletStream();
  }

  void _onClearSearch() {
    setState(() {
      _viewingPlaceName = null;
      _viewingLat = null;
      _viewingLng = null;
    });
    _updateToiletStream();
  }

  void _setupAuth() {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _isSignedIn = true;
      _userId = currentUser.uid;
      _userName = currentUser.displayName;
      // A persisted session is already present at startup (silent resume).
      // This is the exact path that must also ensure the public leaderboard
      // row — otherwise a later points award creates a nameless doc.
      _ensurePublicProfileFor(currentUser);
    }
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      User? user,
    ) {
      if (mounted) {
        setState(() {
          if (user != null) {
            _isSignedIn = true;
            _userId = user.uid;
            _userName = user.displayName;
          } else {
            _isSignedIn = false;
            _userId = null;
            _userName = null;
          }
        });
        if (user != null) {
          _refreshStreak();
          _ensurePublicProfileFor(user);
        } else {
          // Signed out — let the next signed-in user re-ensure their mirror.
          _publicProfileEnsuredUid = null;
        }
      }
    });
  }

  /// Idempotently create/repair `public_profiles/{uid}` for [user], regardless
  /// of how the session arrived (interactive sign-in, silent resume, restart).
  ///
  /// Runs at most once per uid per app session (guarded by
  /// [_publicProfileEnsuredUid]) so repeated auth-state callbacks cannot cause
  /// a write storm. Fire-and-forget: it never blocks app startup, and a failure
  /// is logged and clears the guard so a later auth event can retry — it never
  /// disturbs the auth session itself.
  void _ensurePublicProfileFor(User user) {
    if (_publicProfileEnsuredUid == user.uid) return;
    _publicProfileEnsuredUid = user.uid;
    unawaited(
      _firestoreService
          .ensurePublicProfileMirror(
            user.uid,
            name: user.displayName,
            photoUrl: user.photoURL,
          )
          .catchError((Object e) {
            debugPrint('ensurePublicProfileMirror (non-fatal): $e');
            if (_publicProfileEnsuredUid == user.uid) {
              _publicProfileEnsuredUid = null;
            }
          }),
    );
  }

  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _startToiletStreamWithDefaultLocation();
        return;
      }
      if (permission == LocationPermission.denied) {
        _startToiletStreamWithDefaultLocation();
        return;
      }
      // Get last known position immediately - no GPS lock needed
      final Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _userLat = lastKnown.latitude;
          _userLng = lastKnown.longitude;
          _userPosition = lastKnown;
        });
        _updateToiletStream();
      } else {
        // Start with default Jodhpur while GPS locks - small bounded query
        _startToiletStreamWithDefaultLocation();
      }
      // Then update when fresh GPS arrives.
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              distanceFilter: 500,
            ),
          ).listen((pos) {
            if (!mounted) return;
            // EVERY valid fix updates the current GO/widget
            // position. A 500-900 m move must not be discarded from GO state
            // just because it is below the MAP RECENTER threshold.
            _userPosition = pos;
            unawaited(_refreshGoWidget());

            // Separately: only a large move recenters the map browsing stream.
            final bool mapMoved =
                _userLat == null ||
                (pos.latitude - _userLat!).abs() > 0.01 ||
                (pos.longitude - _userLng!).abs() > 0.01;
            if (mapMoved) {
              setState(() {
                _userLat = pos.latitude;
                _userLng = pos.longitude;
              });
              _updateToiletStream();
            }
          });
    } catch (e) {
      _startToiletStreamWithDefaultLocation();
    }
  }

  void _startToiletStreamWithDefaultLocation() {
    // Use last stored position or Jodhpur fallback - NEVER fetch all toilets
    final double lat = _viewingLat ?? (_userLat ?? 26.2940);
    final double lng = _viewingLng ?? (_userLng ?? 73.0185);
    _toiletsSubscription?.cancel();
    _toilets.clear();
    if (mounted) setState(() {});

    _toiletsSubscription = _firestoreService
        .getToiletsNearby(latitude: lat, longitude: lng, radiusKm: 15.0)
        .listen((toilets) {
          if (mounted) {
            setState(() => _toilets = toilets);
            _updateWidgetWithNearestToilet();
          }
        });
  }

  Future<void> _refreshStreak() async {
    if (_userId == null) return;
    try {
      final streak = await _firestoreService.updateStreak(_userId!);
      if (mounted) setState(() => _streakCount = streak);
    } catch (_) {}
  }

  void _triggerSignInGating(VoidCallback onSuccess) {
    if (FirebaseAuth.instance.currentUser != null) {
      onSuccess();
    } else {
      setState(() {
        _onSignInSuccess = onSuccess;
      });
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (modalContext) => _buildSignInModal(modalContext),
      );
    }
  }

  Widget _buildSmTab(IconData icon, String label, int index) {
    final bool isActive = _selectedTabIndex == index;
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: () {
        CustomHapticsService.playToggleSnap();
        setState(() => _selectedTabIndex = index);
      },
      child: SizedBox(
        width: 72,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            begin: context.sm.ink3,
            end: isActive ? context.sm.brand : context.sm.ink3,
          ),
          duration: SmTokens.dEase,
          builder: (context, color, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 4),
              Text(
                label,
                style: SmText.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabScreen() {
    return IndexedStack(
      index: _selectedTabIndex,
      children: [
        MapScreen(
          toilets: _toilets,
          firestoreService: _firestoreService,
          isSignedIn: _isSignedIn,
          userId: _userId,
          userName: _userName,
          isOnline: _isOnline,
          onSignInRequest: () => _triggerSignInGating(() {}),
          userPosition: _userPosition,
          viewingPlaceName: _viewingPlaceName,
          searchLat: _viewingLat,
          searchLng: _viewingLng,
          streakCount: _streakCount,
          onRefreshToilets: () => setState(() {}),
          onSearchLocationUpdate: _onSearchLocationUpdate,
          onClearSearch: _onClearSearch,
          onSearchPressed: null, // List toggle is now inside MapScreen
          onAccountPressed: () {
            if (_isSignedIn) {
              setState(() => _selectedTabIndex = 1);
            } else {
              _triggerSignInGating(() => setState(() => _selectedTabIndex = 1));
            }
          },
        ),
        ProfileScreen(
          firestoreService: _firestoreService,
          isSignedIn: _isSignedIn,
          userId: _userId,
          onSignInRequest: () => _triggerSignInGating(() {}),
          allToilets: _toilets,
        ),
      ],
    );
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '221425394665-9tsm7hmusivfh12la9htoogl8qeg4hdk.apps.googleusercontent.com',
  );

  // True while a sign-in round-trip is running, so a second tap on the button
  // cannot launch a parallel flow.
  bool _signInInProgress = false;

  Future<void> _handleGoogleSignIn(BuildContext sheetContext) async {
    if (_signInInProgress) return;
    _signInInProgress = true;
    CustomHapticsService.playStepTransition(); // Emulate mechanical double-click for login button
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // `null` is ambiguous: it is returned BOTH on a genuine user
        // cancellation AND when Google Play Services rejects the request
        // before it can raise a PlatformException — most commonly because the
        // installed APK's signing certificate (SHA-1) is not registered for
        // this OAuth client / package (status 10, DEVELOPER_ERROR). We cannot
        // reliably tell the two apart here, so we keep quiet in the UI (no
        // scary error on a real cancel) but leave a breadcrumb in the log.
        debugPrint(
          'GoogleSignIn: signIn() returned null — user cancelled, OR a silent '
          'configuration failure (e.g. status 10 DEVELOPER_ERROR: app '
          'signing SHA-1 not registered for this package).',
        );
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        // Writes profile configuration natively in Firestore with SetOptions(merge: true)
        await _firestoreService.createOrUpdateUser(
          user.uid,
          user.displayName ?? 'Explorer',
          user.email ?? '',
          user.photoURL,
        );
        // createOrUpdateUser has just written the FULL public projection, so
        // mark the mirror ensured for this uid — the authStateChanges callback
        // that follows must not fire a redundant second write.
        _publicProfileEnsuredUid = user.uid;

        if (!mounted) {
          return;
        }
        if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
          Navigator.of(sheetContext).pop();
        }
        setState(() {
          _isSignedIn = true;
          _userId = user.uid;
          _userName = user.displayName;
        });

        showAppSnackBar("Welcome back, ${user.displayName ?? 'Explorer'}!");
        _onSignInSuccess?.call();
      }
    } on PlatformException catch (e) {
      // google_sign_in surfaces native failures here. e.code is the useful,
      // non-secret signal — e.g. 'sign_in_failed' with details
      // 'ApiException: 10' == DEVELOPER_ERROR (SHA-1 / OAuth client mismatch),
      // 'network_error', etc. Never log tokens.
      debugPrint(
        'GoogleSignIn PlatformException: code=${e.code} '
        'message=${e.message} details=${e.details}',
      );
      if (e.code == GoogleSignIn.kSignInCanceledError) {
        return; // genuine cancel — say nothing
      }
      if (!mounted) return;
      showAppSnackBar(
        e.code == GoogleSignIn.kNetworkError
            ? "No connection. Check your internet and try again."
            : "Couldn't sign in with Google. Please try again.",
        isError: true,
      );
    } on FirebaseAuthException catch (e) {
      // Credential handed to Firebase but rejected (bad/expired token, disabled
      // user, account-exists-with-different-credential, …).
      debugPrint(
        'FirebaseAuth signInWithCredential failed: code=${e.code} '
        'message=${e.message}',
      );
      if (!mounted) return;
      showAppSnackBar(
        "Couldn't sign in with Google. Please try again.",
        isError: true,
      );
    } catch (e) {
      debugPrint("Google Sign-In failed (unexpected): $e");
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        "Couldn't sign in with Google. Please try again.",
        isError: true,
      );
    } finally {
      _signInInProgress = false;
    }
  }

  // Sign-in bottom sheet - shown only when a gated action is attempted
  Widget _buildSignInModal(BuildContext sheetContext) {
    return Container(
      decoration: smSheetDecoration(context),
      padding: const EdgeInsets.fromLTRB(
        SmTokens.s24,
        SmTokens.s20,
        SmTokens.s24,
        40.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmGrabHandle(),
          const SizedBox(height: SmTokens.s20),
          Icon(Icons.security, color: context.sm.brand, size: 48.0),
          const SizedBox(height: SmTokens.s16),
          Text(
            'Sign in with Google',
            style: SmText.title.copyWith(color: context.sm.ink),
          ),
          const SizedBox(height: SmTokens.s8),
          Text(
            'Sign in to add toilets, rate, and earn Scout points.',
            textAlign: TextAlign.center,
            style: SmText.body.copyWith(color: context.sm.ink2),
          ),
          const SizedBox(height: SmTokens.s24),
          SmPrimaryButton(
            label: 'Sign in with Google',
            icon: Icons.login,
            onTap: () => _handleGoogleSignIn(sheetContext),
          ),
          const SizedBox(height: SmTokens.s12),
          TextButton(
            onPressed: () {
              CustomHapticsService.playSoftTick();
              Navigator.of(sheetContext).pop();
            },
            child: Text(
              'Maybe later',
              style: SmText.body.copyWith(color: context.sm.ink2),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      Theme.of(context).brightness == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
    );
    return PopScope(
      canPop: _selectedTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedTabIndex != 0) {
          setState(() {
            _selectedTabIndex = 0;
          });
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: context.sm.bg,
        body: Column(
          children: [
            Expanded(child: _buildActiveTabScreen()),
            // Seamless white nav — big GO notched into the bar
            Container(
              decoration: BoxDecoration(
                color: context.sm.surface,
                boxShadow: [
                  BoxShadow(
                    color: context.sm.ink.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 76,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Center(
                              child: _buildSmTab(Icons.map_rounded, 'Map', 0),
                            ),
                          ),
                          const SizedBox(
                            width: 84,
                          ), // equals GO diameter — each Expanded spans edge→circle edge
                          Expanded(
                            child: Center(
                              child: _buildSmTab(
                                Icons.person_rounded,
                                'You',
                                1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: -30,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              CustomHapticsService.playCrispSuccess();
                              _startEmergencyFlow();
                            },
                            onLongPress: _startAddToiletFlow,
                            child: Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: context.sm.brandSolid,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: context.sm.surface,
                                  width: 4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.sm.brandSolid.withValues(
                                      alpha: 0.40,
                                    ),
                                    blurRadius: 18,
                                    spreadRadius: -2,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    color: context.sm.onBrand,
                                    size: 30,
                                  ),
                                  Text(
                                    'GO',
                                    style: SmText.eyebrow.copyWith(
                                      color: context.sm.onBrand,
                                      fontSize: 10,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
