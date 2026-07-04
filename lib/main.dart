// ┌─────────────────────────────────────────────────────────────────────────┐
// │  ShauchMap — शौच Map                                                    │
// │  Find the nearest clean public toilet in India.                         │
// │                                                                         │
// │  Built by @yodevstudio · github.com/yodevstudio                        │
// │  Open-source under MIT. If you're reading this — welcome to the code.  │
// │  Every toilet on this map was put here by someone who gave a damn. ✦   │
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
    show
        GoogleMap,
        CameraPosition,
        Marker,
        MarkerId,
        Polyline,
        PolylineId,
        PatternItem,
        BitmapDescriptor;

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
        if (position == null) return true;

        final fs = FirestoreService();
        final stream = fs.getToiletsNearby(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusKm: 15.0,
        );
        final toilets = await stream.first;
        final openToilets = toilets.where((t) => t.isOpen).toList();

        if (openToilets.isNotEmpty) {
          // Sort by distance
          openToilets.sort((a, b) {
            final distA = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              a.latitude,
              a.longitude,
            );
            final distB = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              b.latitude,
              b.longitude,
            );
            return distA.compareTo(distB);
          });

          // Small widget
          final nearest = openToilets.first;
          final minDist = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            nearest.latitude,
            nearest.longitude,
          );
          int walkMin = (minDist / 80).ceil();

          HomeWidget.saveWidgetData<String>('nearest_loo_name', nearest.name);
          HomeWidget.saveWidgetData<String>(
            'nearest_loo_dist',
            '${formatDistance(minDist)} \u2022 $walkMin min',
          );
          HomeWidget.saveWidgetData<String>('toilet_id', nearest.id);

          final now = DateTime.now();
          final hour = now.hour > 12
              ? now.hour - 12
              : (now.hour == 0 ? 12 : now.hour);
          final ampm = now.hour >= 12 ? 'PM' : 'AM';
          final minute = now.minute.toString().padLeft(2, '0');
          final lastUpdated = "Last updated $hour:$minute $ampm";
          HomeWidget.saveWidgetData<String>('last_updated', lastUpdated);

          HomeWidget.updateWidget(
            name: 'WidgetProvider',
            androidName: 'WidgetProvider',
          );

          // Medium widget
          for (int i = 0; i < 3; i++) {
            if (i < openToilets.length) {
              final t = openToilets[i];
              final dist = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                t.latitude,
                t.longitude,
              );
              int wMin = (dist / 80).ceil();
              HomeWidget.saveWidgetData<String>('med_${i + 1}_name', t.name);
              HomeWidget.saveWidgetData<String>(
                'med_${i + 1}_dist',
                '${formatDistance(dist)} \u2022 $wMin min',
              );
              HomeWidget.saveWidgetData<String>('med_${i + 1}_id', t.id);
            } else {
              HomeWidget.saveWidgetData<String>('med_${i + 1}_name', '');
              HomeWidget.saveWidgetData<String>('med_${i + 1}_dist', '');
              HomeWidget.saveWidgetData<String>('med_${i + 1}_id', '');
            }
          }
          HomeWidget.updateWidget(
            name: 'WidgetProviderMedium',
            androidName: 'WidgetProviderMedium',
          );
        }
      } catch (e) {
        debugPrint("Workmanager error: $e");
      }
    }
    return true;
  });
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
  runApp(const LooMapApp());
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

class LooMapApp extends StatelessWidget {
  const LooMapApp({super.key});

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
                          targetToilet = Toilet.fromFirestore(doc);
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

    if (uri.host == 'emergency') {
      _startEmergencyFlow();
    } else if (uri.host == 'navigate') {
      final toiletId = uri.queryParameters['toiletId'];
      if (toiletId != null && toiletId.isNotEmpty) {
        _launchToiletNav(toiletId);
      }
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
                    'Finding the nearest open toilet…',
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

  void _launchToiletNav(String toiletId) async {
    if (_isNavigatingFlowActive) {
      return;
    }
    _isNavigatingFlowActive = true;
    try {
      if (_toilets.isEmpty || _userPosition == null || !mounted) {
        return;
      }
      final toilet = _toilets.firstWhereOrNull((t) => t.id == toiletId);
      if (toilet == null) {
        if (mounted) {
          showAppSnackBar('Toilet not found in loaded area', isError: true);
        }
        return;
      }
      final dist = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        toilet.latitude,
        toilet.longitude,
      );
      final selectedMode = await showTravelModeSheet(
        context,
        distanceMeters: dist,
      );
      if (selectedMode == null) {
        return;
      }
      if (!mounted) {
        return;
      }

      int etaSeconds;
      if (selectedMode == TravelMode.driving) {
        etaSeconds = (dist / 11.1).round();
      } else if (selectedMode == TravelMode.bicycling) {
        etaSeconds = (dist / 4.1).round();
      } else {
        etaSeconds = (dist / 1.4).round();
      }

      _dismissEmergencyDialog();

      await MapLauncher.launch(
        destination: LatLng(toilet.latitude, toilet.longitude),
        toiletName: toilet.name,
        toiletId: toilet.id,
        etaSeconds: etaSeconds,
        mode: selectedMode,
      );
    } catch (_) {
      if (mounted) {
        showAppSnackBar('Toilet not found in loaded area', isError: true);
      }
    } finally {
      _isNavigatingFlowActive = false;
      _dismissEmergencyDialog();
    }
  }

  Future<void> _showGoPreviewSheet(
    BuildContext ctx,
    Toilet nearest,
    double distMeters,
  ) async {
    final userLatLng = LatLng(
      _userPosition!.latitude,
      _userPosition!.longitude,
    );
    final toiletLatLng = LatLng(nearest.latitude, nearest.longitude);
    final midPoint = LatLng(
      (userLatLng.latitude + toiletLatLng.latitude) / 2,
      (userLatLng.longitude + toiletLatLng.longitude) / 2,
    );
    final walkMin = (distMeters / 80).ceil();

    await showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final c = ctx.sm;
        return Container(
          decoration: smSheetDecoration(ctx),
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
                  const SmEyebrow('NEAREST USABLE TOILET · RIGHT NOW'),
                  const SizedBox(height: SmTokens.s12),
                  // Mini-map
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SmTokens.rCard),
                    child: SizedBox(
                      height: 150,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: midPoint,
                          zoom: 15,
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
                              BitmapDescriptor.hueGreen,
                            ),
                          ),
                        },
                        polylines: {
                          Polyline(
                            polylineId: const PolylineId('route'),
                            points: [userLatLng, toiletLatLng],
                            color: c.brandSolid,
                            width: 3,
                            patterns: [
                              PatternItem.dash(12),
                              PatternItem.gap(8),
                            ],
                          ),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: SmTokens.s16),
                  // Hero distance + name + status + walk time
                  Builder(
                    builder: (context) {
                      final (goNum, goUnit) = formatDistanceParts(distMeters);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
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
                                  style: SmText.subhead.copyWith(color: c.ink2),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: SmTokens.s16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nearest.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: SmText.subhead.copyWith(
                                    color: c.ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: SmTokens.s4),
                                const SizedBox(height: SmTokens.s4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SmStatusLabel(
                                      nearest.isOpen
                                          ? SmStatus.open
                                          : SmStatus.closed,
                                    ),
                                    const SizedBox(width: SmTokens.s8),
                                    Icon(
                                      Icons.directions_walk,
                                      size: 14,
                                      color: c.ink3,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '$walkMin min',
                                      style: SmText.caption.copyWith(
                                        color: c.ink2,
                                      ),
                                    ),
                                    if (nearest.totalRatings > 0) ...[
                                      const SizedBox(width: SmTokens.s8),
                                      Text(
                                        '★ ${nearest.starRating.toStringAsFixed(1)}',
                                        style: SmText.caption.copyWith(
                                          color: c.ink2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: SmTokens.s16),
                  SmPrimaryButton(
                    label: 'Navigate in Maps',
                    icon: Icons.near_me_rounded,
                    onTap: () async {
                      Navigator.of(sheetCtx).pop();
                      if (!mounted) {
                        return;
                      }
                      final selectedMode = await showTravelModeSheet(
                        ctx,
                        distanceMeters: distMeters,
                      );
                      if (selectedMode == null || !mounted) return;
                      final etaSeconds = selectedMode == TravelMode.driving
                          ? (distMeters / 11.1).round()
                          : selectedMode == TravelMode.bicycling
                          ? (distMeters / 4.1).round()
                          : (distMeters / 1.4).round();
                      await MapLauncher.launch(
                        destination: toiletLatLng,
                        toiletName: nearest.name,
                        toiletId: nearest.id,
                        etaSeconds: etaSeconds,
                        mode: selectedMode,
                      );
                    },
                  ),
                  const SizedBox(height: SmTokens.s12),
                  GestureDetector(
                    onTap: () async {
                      Navigator.of(sheetCtx).pop();
                      if (!mounted) {
                        return;
                      }
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
                                border: Border.all(
                                  color: context.sm.line,
                                  width: 1,
                                ),
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
                                      onSignInRequest: () =>
                                          _triggerSignInGating(() {}),
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
                    },
                    child: Text.rich(
                      TextSpan(
                        text: 'Need something specific?  ',
                        style: SmText.caption.copyWith(color: c.ink3),
                        children: [
                          TextSpan(
                            text: 'Alternatives ↑',
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
        );
      },
    );
  }

  void _startAddToiletFlow() {
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

  Future<void> _startEmergencyFlow() async {
    if (_isNavigatingFlowActive) {
      return;
    }
    _isNavigatingFlowActive = true;
    try {
      // COLD-START GPS SAFETY GATE
      // Try last-known first — avoids the loader entirely when position is fresh.
      final posAge = _userPosition != null
          ? DateTime.now().difference(_userPosition!.timestamp).inSeconds
          : 999;
      if (posAge > 10) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null &&
            DateTime.now().difference(lastKnown.timestamp).inSeconds < 30) {
          _userPosition = lastKnown;
        } else {
          // Last-known is stale or absent — show loader and fetch fresh.
          _showEmergencyDialog();
          try {
            final position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 4),
              ),
            );
            _userPosition = position;
          } catch (_) {
            _userPosition = lastKnown ?? _userPosition;
          }
          _dismissEmergencyDialog();
        }
      }

      if (_userPosition == null || _toilets.isEmpty) {
        if (mounted) {
          showAppSnackBar('Cannot locate nearest loo right now', isError: true);
        }
        return;
      }

      Toilet? nearest;
      double minDistance = double.infinity;
      for (final t in _toilets) {
        if (!t.isOpen) {
          continue;
        }
        final dist = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          t.latitude,
          t.longitude,
        );
        if (dist < minDistance) {
          minDistance = dist;
          nearest = t;
        }
      }

      if (nearest != null && mounted) {
        _dismissEmergencyDialog();
        await _showGoPreviewSheet(context, nearest, minDistance);
      }
    } finally {
      _isNavigatingFlowActive = false;
      _dismissEmergencyDialog();
    }
  }

  void _updateWidgetWithNearestToilet() {
    if (_userPosition == null || _toilets.isEmpty) return;

    final openToilets = _toilets.where((t) => t.isOpen).toList();
    if (openToilets.isEmpty) return;

    openToilets.sort((a, b) {
      final distA = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        a.latitude,
        a.longitude,
      );
      final distB = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        b.latitude,
        b.longitude,
      );
      return distA.compareTo(distB);
    });

    final nearest = openToilets.first;
    final minDist = Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      nearest.latitude,
      nearest.longitude,
    );
    int walkMin = (minDist / 80).ceil();

    // Small widget
    HomeWidget.saveWidgetData<String>('nearest_loo_name', nearest.name);
    HomeWidget.saveWidgetData<String>(
      'nearest_loo_dist',
      '${formatDistance(minDist)} \u2022 $walkMin min',
    );
    HomeWidget.saveWidgetData<String>('toilet_id', nearest.id);

    final now = DateTime.now();
    final hour = now.hour > 12
        ? now.hour - 12
        : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final minute = now.minute.toString().padLeft(2, '0');
    final lastUpdated = "Last updated $hour:$minute $ampm";
    HomeWidget.saveWidgetData<String>('last_updated', lastUpdated);

    HomeWidget.updateWidget(
      name: 'WidgetProvider',
      androidName: 'WidgetProvider',
    );

    // Medium widget
    for (int i = 0; i < 3; i++) {
      if (i < openToilets.length) {
        final t = openToilets[i];
        final dist = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          t.latitude,
          t.longitude,
        );
        int wMin = (dist / 80).ceil();
        HomeWidget.saveWidgetData<String>('med_${i + 1}_name', t.name);
        HomeWidget.saveWidgetData<String>(
          'med_${i + 1}_dist',
          '${formatDistance(dist)} \u2022 $wMin min',
        );
        HomeWidget.saveWidgetData<String>('med_${i + 1}_id', t.id);
      } else {
        HomeWidget.saveWidgetData<String>('med_${i + 1}_name', '');
        HomeWidget.saveWidgetData<String>('med_${i + 1}_dist', '');
        HomeWidget.saveWidgetData<String>('med_${i + 1}_id', '');
      }
    }
    HomeWidget.updateWidget(
      name: 'WidgetProviderMedium',
      androidName: 'WidgetProviderMedium',
    );
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
        if (user != null) _refreshStreak();
      }
    });
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
      // Then update when fresh GPS arrives
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              distanceFilter: 500,
            ),
          ).listen((pos) {
            if (mounted) {
              final bool moved =
                  _userLat == null ||
                  (pos.latitude - _userLat!).abs() > 0.01 ||
                  (pos.longitude - _userLng!).abs() > 0.01;
              if (moved) {
                setState(() {
                  _userLat = pos.latitude;
                  _userLng = pos.longitude;
                  _userPosition = pos;
                });
                _updateToiletStream();
              }
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

  Future<void> _handleGoogleSignIn(BuildContext sheetContext) async {
    CustomHapticsService.playStepTransition(); // Emulate mechanical double-click for login button
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // User cancelled the flow

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
    } catch (e) {
      debugPrint("Google Sign-In failed: $e");
      if (!mounted) {
        return;
      }
      showAppSnackBar("Google Sign-In failed: $e", isError: true);
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
