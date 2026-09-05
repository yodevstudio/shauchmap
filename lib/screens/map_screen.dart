import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geocoding/geocoding.dart';
import '../services/firestore_service.dart';
import '../services/custom_haptics_service.dart';
import '../services/orientation_engine.dart';
import '../map_style.dart';
import 'detail_sheet.dart';
import 'list_screen.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';
import '../widgets/sm_states.dart';
import '../widgets/evidence_status_label.dart';
import '../widgets/osm_attribution_badge.dart';

import 'package:collection/collection.dart';

enum CameraTrackMode { gps, toilet, free }

// (Removed) : there is no vote-derived "spam" auto-hide. A vote is
// OPINION, not identity confirmation or moderation authority — a coordinated
// set of accounts must not be able to suppress a real facility from browse
// results. Votes are shown as opinion evidence only; removal/hiding must come
// from a defined moderation / identity-confirmation process (not built here).

class MapScreen extends StatefulWidget {
  final List<Toilet> toilets;
  final FirestoreService firestoreService;
  final bool isSignedIn;
  final String? userId;
  final String? userName;
  final bool isOnline;
  final VoidCallback onSignInRequest;
  final VoidCallback onRefreshToilets;
  final VoidCallback? onSearchPressed;
  final VoidCallback? onAccountPressed;
  final String? viewingPlaceName;
  final VoidCallback? onClearSearch;
  final void Function(String, double, double)? onSearchLocationUpdate;
  final Position? userPosition;
  final double? searchLat;
  final double? searchLng;
  final int streakCount;

  const MapScreen({
    super.key,
    required this.toilets,
    required this.firestoreService,
    required this.isSignedIn,
    required this.userId,
    required this.userName,
    required this.isOnline,
    required this.onSignInRequest,
    required this.onRefreshToilets,
    this.onSearchPressed,
    this.onAccountPressed,
    this.onSearchLocationUpdate,
    this.viewingPlaceName,
    this.onClearSearch,
    this.userPosition,
    this.searchLat,
    this.searchLng,
    this.streakCount = 0,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  Toilet? _selectedToilet;
  final OrientationEngine _orientationEngine = OrientationEngine();
  // honesty pass: only "Water listed" survives — it selects toilets
  // whose source positively listed water. "Open Now" / "Free" / "Western" /
  // "Women Safe" filtered on importer defaults and missing fields, so they
  // turned "unknown" into a false "no" and were removed.
  bool _filterOnlyWater = false;
  String _cityName = 'Locating...';
  PageController? _pageController;
  Timer? _prefetchTimer;

  // ignore: unused_field
  bool _isProgrammaticPageScroll = false;

  List<Toilet> _cachedSortedToilets = [];
  // ignore: unused_field
  Map<String, double> _scoreCache = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    _updateSortedToilets();
    if (widget.userPosition != null) {
      _updateCityName(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
      );
    }
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toilets != oldWidget.toilets) {
      _updateSortedToilets();
      if (_selectedToilet != null) {
        _selectedToilet = widget.toilets.firstWhereOrNull(
          (t) => t.id == _selectedToilet!.id,
        );
      }
    }

    if (widget.userPosition != oldWidget.userPosition &&
        widget.userPosition != null) {
      // First position fix - centre the map once
      if (oldWidget.userPosition == null && widget.searchLat == null) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(
                widget.userPosition!.latitude,
                widget.userPosition!.longitude,
              ),
              zoom: 15.0,
            ),
          ),
        );
      }
      _updateCityName(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
      );
      _updateSortedToilets();
    }
  }

  @override
  void dispose() {
    _prefetchTimer?.cancel();
    _pageController?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _setSelectedToilet(Toilet toilet) {
    if (_selectedToilet?.id == toilet.id) return;
    setState(() {
      _selectedToilet = toilet;
    });
  }

  void _updateSortedToilets() {
    List<Toilet> list = List.from(widget.toilets);
    // NO automatic crowd-threshold hiding. Votes never remove a toilet from
    // browse results (see the note near the top of this file).
    // Only positive source/submitter evidence filters the list now (Truth V2).
    if (_filterOnlyWater) {
      list = list
          .where((t) => t.truth.amenities.water == EvidenceState.present)
          .toList();
    }

    final Map<String, double> localCache = {};
    for (final t in list) {
      localCache[t.id] = _calculateMatchScore(t);
    }

    list.sort((a, b) {
      final sa = localCache[a.id] ?? 0.0;
      final sb = localCache[b.id] ?? 0.0;
      return sb.compareTo(sa);
    });

    setState(() {
      _scoreCache = localCache;
      _cachedSortedToilets = list;
    });
  }

  Future<void> _updateCityName(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        lat,
        lng,
      ).timeout(const Duration(seconds: 5));
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
            p.administrativeArea!,
        ];
        setState(() {
          _cityName = parts.isNotEmpty ? parts.join(', ') : 'Near You';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cityName = 'Near You');
    }
  }

  // the old "match score" blended a freshness curve (always the null
  // floor — no toilet has `last_verified`), a Bayesian rating (always the
  // 3.5 prior — no toilet has ratings) and an `is_open` bonus (importer
  // default). That dressed distance up as a reliability ranking. Ordering is
  // now purely nearest-first; the returned value is a monotonic proximity
  // score so callers that sort descending still get nearest-first.
  double _calculateMatchScore(Toilet toilet) {
    if (widget.userPosition == null) return 0.0;
    final double distMeters = Geolocator.distanceBetween(
      widget.userPosition!.latitude,
      widget.userPosition!.longitude,
      toilet.latitude,
      toilet.longitude,
    );
    return exp(-distMeters / 400.0);
  }

  Widget _buildFilterChip(
    String label,
    bool isSelected,
    ValueChanged<bool> onChanged,
  ) {
    return SmFilterChip(
      label: label,
      selected: isSelected,
      onTap: () => onChanged(!isSelected),
    );
  }

  void _openDetailSheet(Toilet toilet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: DetailSheet(
            toilet: toilet,
            userPosition: widget.userPosition,
            isSignedIn: widget.isSignedIn,
            userId: widget.userId,
            userName: widget.userName,
            onSignInRequest: widget.onSignInRequest,
            onRefreshToilets: widget.onRefreshToilets,
          ),
        );
      },
    );
  }

  String? _calculateDistanceText(Toilet toilet) {
    if (widget.userPosition == null) return null;
    final double distance = Geolocator.distanceBetween(
      widget.userPosition!.latitude,
      widget.userPosition!.longitude,
      toilet.latitude,
      toilet.longitude,
    );
    return "${distance.toInt()}m";
  }

  // ---- Peek-sheet + browse helpers ----
  // The map peek sheet makes NO recency or rating claim. There is no
  // per-toilet condition data here, `last_verified` is missing on every
  // production toilet, and the parent star_rating / total_ratings fields are
  // frozen (Secure Contributions never writes them) so any figure would be
  // stale. Ratings are shown honestly, aggregated on read, in the detail sheet.
  // A derived index could restore a real peek summary in the future.

  void _openSearchSheet() {
    CustomHapticsService.playToggleSnap();
    showModalBottomSheet(
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
                    toilets: widget.toilets,
                    firestoreService: widget.firestoreService,
                    isSignedIn: widget.isSignedIn,
                    userId: widget.userId,
                    userName: widget.userName,
                    onSignInRequest: widget.onSignInRequest,
                    onRefreshToilets: widget.onRefreshToilets,
                    userPosition: widget.userPosition,
                    viewingPlaceName: widget.viewingPlaceName,
                    onSearchLocationUpdate: widget.onSearchLocationUpdate,
                    onClearSearch: widget.onClearSearch,
                    searchMode: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openBrowseSheet() {
    CustomHapticsService.playToggleSnap();
    showModalBottomSheet(
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
                    toilets: widget.toilets,
                    firestoreService: widget.firestoreService,
                    isSignedIn: widget.isSignedIn,
                    userId: widget.userId,
                    userName: widget.userName,
                    onSignInRequest: widget.onSignInRequest,
                    onRefreshToilets: widget.onRefreshToilets,
                    userPosition: widget.userPosition,
                    viewingPlaceName: widget.viewingPlaceName,
                    onSearchLocationUpdate: widget.onSearchLocationUpdate,
                    onClearSearch: widget.onClearSearch,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeekSheet(BuildContext context, Toilet t, int totalNearby) {
    final c = context.sm;
    final dist = _calculateDistanceText(t);
    // Ratings line only; the status label is a self-expiring EvidenceStatusLabel.
    final pt = ToiletPresentation.fromEvidence(t);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SmTokens.rSheet),
        ),
        border: Border.all(color: c.line, width: 1),
        boxShadow: context.smHeavy,
      ),
      padding: const EdgeInsets.fromLTRB(
        SmTokens.s20,
        SmTokens.s8,
        SmTokens.s20,
        SmTokens.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: GestureDetector(
              onTap: _openBrowseSheet,
              child: const SmGrabHandle(),
            ),
          ),
          const SizedBox(height: SmTokens.s12),
          const SmEyebrow('Nearest toilet'),
          const SizedBox(height: SmTokens.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dist?.replaceAll('m', '') ?? '—',
                    style: SmText.hero.copyWith(color: c.ink, height: 1.0),
                  ),
                  const SizedBox(width: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'm',
                      style: SmText.subhead.copyWith(color: c.ink2),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: SmTokens.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmText.subhead.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: SmTokens.s4),
                    // Only a CURRENT server-derived condition summary can move
                    // this off "Status unconfirmed"; it self-expires when the
                    // evidence window passes (no polling).
                    EvidenceStatusLabel(t),
                    if (pt.ratingsLabel != null) ...[
                      const SizedBox(height: SmTokens.s4),
                      Text(
                        pt.ratingsLabel!,
                        style: SmText.caption.copyWith(color: c.ink2),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SmTokens.s12),
          SmPrimaryButton(
            label: 'Navigate',
            icon: Icons.near_me_rounded,
            onTap: () => _openDetailSheet(t),
          ),
          const SizedBox(height: SmTokens.s8),
          Center(
            child: GestureDetector(
              onTap: _openBrowseSheet,
              child: Text(
                'See all $totalNearby nearby   ↑',
                style: SmText.caption.copyWith(
                  color: c.ink2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toilets = _cachedSortedToilets;
    if (toilets.isNotEmpty) {
      _selectedToilet = _selectedToilet != null
          ? toilets.firstWhere(
              (t) => t.id == _selectedToilet!.id,
              orElse: () => toilets[0],
            )
          : toilets[0];
    } else {
      _selectedToilet = null;
    }

    final topInset = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // 1 -- Full-bleed map
        Positioned.fill(
          child: MapCanvas(
            toilets: toilets,
            selectedToilet: _selectedToilet,
            orientationEngine: _orientationEngine,
            currentUserLatLng: widget.userPosition != null
                ? LatLng(
                    widget.userPosition!.latitude,
                    widget.userPosition!.longitude,
                  )
                : const LatLng(26.2940, 73.0185),
            onToiletSelected: (toilet) {
              _setSelectedToilet(toilet);
              final idx = toilets.indexWhere((t) => t.id == toilet.id);
              if (idx != -1 && _pageController != null) {
                _isProgrammaticPageScroll = true;
                _pageController!
                    .animateToPage(
                      idx,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    )
                    .then((_) => _isProgrammaticPageScroll = false);
              }
            },
            onMapCreated: (controller) {
              _mapController = controller;
              CustomHapticsService.playStepTransition();
            },
          ),
        ),

        // 2 -- Floating search pill + filter button + quick chips
        Positioned(
          top: topInset + 10,
          left: 0,
          right: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SmTokens.s16),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _openSearchSheet,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(
                            horizontal: SmTokens.s12,
                          ),
                          decoration: BoxDecoration(
                            color: context.sm.surface,
                            borderRadius: BorderRadius.circular(
                              SmTokens.rSmall,
                            ),
                            border: Border.all(
                              color: context.sm.line,
                              width: 1,
                            ),
                            boxShadow: context.smSoft,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search,
                                size: 20,
                                color: context.sm.ink3,
                              ),
                              const SizedBox(width: SmTokens.s8),
                              Expanded(
                                child: Text(
                                  widget.viewingPlaceName ??
                                      ((_cityName == 'Locating...' ||
                                              _cityName == 'Near You')
                                          ? 'Search area'
                                          : '$_cityName · search area'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SmText.body.copyWith(
                                    color: context.sm.ink3,
                                  ),
                                ),
                              ),
                              if (widget.viewingPlaceName != null)
                                GestureDetector(
                                  onTap: () {
                                    CustomHapticsService.playToggleSnap();
                                    widget.onClearSearch?.call();
                                  },
                                  child: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: context.sm.ink3,
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
              const SizedBox(height: SmTokens.s8),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: SmTokens.s16),
                  children: [
                    _buildFilterChip('Water listed', _filterOnlyWater, (v) {
                      setState(() {
                        _filterOnlyWater = v;
                        _updateSortedToilets();
                      });
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3 -- Offline banner
        if (!widget.isOnline)
          Positioned(
            top: topInset + 104,
            left: SmTokens.s16,
            right: SmTokens.s16,
            child: SmStateView.offline(),
          ),

        // 4 -- Bottom peek sheet, with the OSM data attribution pinned just
        // above its top edge (ODbL requires the credit be user-visible, not
        // only documented in the repo). The badge lives in the SAME
        // bottom-anchored slot as the sheet and above it in a Column, so it
        // always sits just above the white card regardless of the card's
        // content height — never drifting onto it (an earlier fixed bottom
        // offset did exactly that once the sheet grew taller than assumed).
        if (_selectedToilet != null && toilets.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(
                    left: SmTokens.s8,
                    bottom: SmTokens.s8,
                  ),
                  child: OsmAttributionBadge(),
                ),
                _buildPeekSheet(
                  context,
                  _selectedToilet!,
                  widget.toilets.length,
                ),
              ],
            ),
          )
        else
          // No selection -> no white card. Keep the credit visible, anchored
          // just above the bottom padding the GoogleMap reserves for Google's
          // own logo/legal attribution, clear of the map controls.
          Positioned(
            left: SmTokens.s8,
            bottom:
                (MediaQuery.of(context).size.height < 600 ? 150.0 : 180.0) +
                SmTokens.s8,
            child: const OsmAttributionBadge(),
          ),
      ],
    );
  }
}

class MapCanvas extends StatefulWidget {
  final List<Toilet> toilets;
  final Toilet? selectedToilet;
  final ValueChanged<Toilet> onToiletSelected;
  final Function(GoogleMapController) onMapCreated;
  final LatLng? currentUserLatLng;
  final OrientationEngine orientationEngine;
  final double? searchLat;
  final double? searchLng;
  final void Function(String, double, double)? onSearchLocationUpdate;

  const MapCanvas({
    super.key,
    required this.toilets,
    required this.selectedToilet,
    required this.onToiletSelected,
    required this.onMapCreated,
    this.currentUserLatLng,
    required this.orientationEngine,
    this.searchLat,
    this.searchLng,
    this.onSearchLocationUpdate,
  });

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  OrientationEngine get _orientationEngine => widget.orientationEngine;
  GoogleMapController? _mapController;

  final bool _is3DMode = false;
  double _smoothedHeading = 0.0;

  CameraTrackMode _cameraTrackMode = CameraTrackMode.gps;

  bool _isUserDraggingMap = false;
  bool _isAnimatingProgrammatically = false;

  bool _isUserInteracting = false;

  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _latestCompass;

  Set<Marker> _cachedMarkers = {};
  String? _lastToiletsKey;
  String _toiletsStateKey = '';

  Toilet? _visualSelectedToilet;
  CameraPosition? _currentCameraPosition;
  LatLngBounds? _visibleBounds;
  double _zoom = 13.5;
  bool _showSearchThisArea = false;

  @override
  void didUpdateWidget(covariant MapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toilets != oldWidget.toilets) {
      // Markers depend only on id + the moderation flag now (condition
      // evidence no longer colours a pin), so no time-varying value in the key.
      _toiletsStateKey = widget.toilets
          .map((t) => '${t.id}${t.isFlagged}')
          .join(',');
    }
    if (widget.searchLat != oldWidget.searchLat ||
        widget.searchLng != oldWidget.searchLng) {
      if (widget.searchLat != null && widget.searchLng != null) {
        setState(() {
          _showSearchThisArea = false;
          _isUserInteracting = false; // Unpause so it can jump
        });
        _isAnimatingProgrammatically = true;
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(widget.searchLat!, widget.searchLng!),
              zoom: 15.0,
            ),
          ),
        );
      }
    }

    if (widget.currentUserLatLng != oldWidget.currentUserLatLng &&
        widget.currentUserLatLng != null) {
      _onSensorUpdate(widget.currentUserLatLng, _latestCompass);
    }

    if (widget.selectedToilet?.id != oldWidget.selectedToilet?.id) {
      setState(() {
        _visualSelectedToilet = widget.selectedToilet;
        _isUserInteracting = false; // Unpause so carousel can jump to toilet
      });
      if (!_isUserDraggingMap) {
        _cameraTrackMode = CameraTrackMode.toilet;
        _isAnimatingProgrammatically =
            true; // Lock sensors until native glide finishes

        if (widget.selectedToilet != null) {
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(
                  widget.selectedToilet!.latitude,
                  widget.selectedToilet!.longitude,
                ),
                zoom: 16.0,
                tilt: _is3DMode ? 45.0 : 0.0,
                bearing: _is3DMode ? _smoothedHeading : 0.0,
              ),
            ),
          );
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _visualSelectedToilet = widget.selectedToilet;
    _toiletsStateKey = widget.toilets
        .map((t) => '${t.id}${t.isFlagged}')
        .join(',');
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  void _startSensorStreams() {
    if (_compassSubscription != null) return;

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted) {
        _latestCompass = event.heading;
        _onSensorUpdate(widget.currentUserLatLng, _latestCompass);
      }
    });

    if (widget.currentUserLatLng != null) {
      _onSensorUpdate(widget.currentUserLatLng, _latestCompass);
    }
  }

  void _onSensorUpdate(LatLng? gps, double? compass) {
    if (_isUserInteracting) return;
    if (_mapController == null || gps == null) return;

    // COMPASS ONLY UPDATES IF WE ARE NOT GLIDING OR DRAGGING
    if (_isUserDraggingMap || _isAnimatingProgrammatically) return;

    // Stop continuous sensor updates when the map is in free-look mode
    if (_cameraTrackMode == CameraTrackMode.free) return;
    if (!_is3DMode) return;

    LatLng target;
    switch (_cameraTrackMode) {
      case CameraTrackMode.gps:
        target = gps;
        break;
      case CameraTrackMode.toilet:
        if (_visualSelectedToilet != null) {
          target = LatLng(
            _visualSelectedToilet!.latitude,
            _visualSelectedToilet!.longitude,
          );
        } else {
          target = gps;
        }
        break;
      case CameraTrackMode.free:
        target = _currentCameraPosition?.target ?? gps;
        break;
    }

    double bearing = _smoothedHeading;
    if (compass != null) {
      _smoothedHeading = _orientationEngine.calculateSmoothedBearing(compass);
      bearing = _smoothedHeading;
    }

    final double tilt = _is3DMode ? 45.0 : 0.0;
    final double zoom = _currentCameraPosition?.zoom ?? 15.5;

    try {
      _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: zoom,
            tilt: tilt,
            bearing: bearing,
          ),
        ),
      );
    } catch (_) {}
  }

  Set<Marker> _getMarkers() {
    String currentKey = _toiletsStateKey + (_visualSelectedToilet?.id ?? '');

    if (_visibleBounds != null) {
      currentKey +=
          ',b:${_visibleBounds!.southwest.latitude.toStringAsFixed(3)},${_visibleBounds!.southwest.longitude.toStringAsFixed(3)},${_visibleBounds!.northeast.latitude.toStringAsFixed(3)},${_visibleBounds!.northeast.longitude.toStringAsFixed(3)}';
    }
    currentKey += ',z:${_zoom.toStringAsFixed(1)}';

    if (_lastToiletsKey == currentKey && _cachedMarkers.isNotEmpty) {
      return _cachedMarkers;
    }
    _lastToiletsKey = currentKey;

    final Set<Marker> markers = {};
    if (_zoom < 15) {
      final double degPerPx = 360 / (256 * pow(2, _zoom));
      final double cell = 70 * degPerPx;
      final Map<String, List<Toilet>> buckets = {};

      for (final toilet in widget.toilets) {
        if (_visibleBounds != null) {
          final double latSpan =
              (_visibleBounds!.northeast.latitude -
                      _visibleBounds!.southwest.latitude)
                  .abs();
          final double lngSpan =
              (_visibleBounds!.northeast.longitude -
                      _visibleBounds!.southwest.longitude)
                  .abs();
          final double expandedSouth =
              _visibleBounds!.southwest.latitude - (latSpan * 0.2);
          final double expandedNorth =
              _visibleBounds!.northeast.latitude + (latSpan * 0.2);
          final double expandedWest =
              _visibleBounds!.southwest.longitude - (lngSpan * 0.2);
          final double expandedEast =
              _visibleBounds!.northeast.longitude + (lngSpan * 0.2);

          if (toilet.latitude < expandedSouth ||
              toilet.latitude > expandedNorth ||
              toilet.longitude < expandedWest ||
              toilet.longitude > expandedEast) {
            continue;
          }
        }

        final String bucketKey =
            '${(toilet.latitude / cell).floor()}_${(toilet.longitude / cell).floor()}';
        buckets.putIfAbsent(bucketKey, () => []).add(toilet);
      }

      for (final bucket in buckets.values) {
        if (bucket.length > 1) {
          double sumLat = 0, sumLng = 0;
          for (final t in bucket) {
            sumLat += t.latitude;
            sumLng += t.longitude;
          }
          final centroid = LatLng(
            sumLat / bucket.length,
            sumLng / bucket.length,
          );
          markers.add(
            Marker(
              markerId: MarkerId(
                'cluster_${centroid.latitude}_${centroid.longitude}',
              ),
              position: centroid,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueCyan,
              ),
              infoWindow: InfoWindow(title: '${bucket.length} toilets'),
              zIndexInt: 3,
              consumeTapEvents: true,
              onTap: () {
                CustomHapticsService.playSpringBounce();
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(centroid, _zoom + 2),
                );
              },
            ),
          );
        } else {
          final toilet = bucket.first;
          final bool isSelected = toilet.id == _visualSelectedToilet?.id;
          markers.add(
            Marker(
              markerId: MarkerId(toilet.id),
              position: LatLng(toilet.latitude, toilet.longitude),
              icon: toiletMarkerIcon(toilet, isSelected),
              zIndexInt: isSelected ? 2 : 1,
              consumeTapEvents: true,
              onTap: () {
                CustomHapticsService.playSpringBounce();
                widget.onToiletSelected(toilet);
              },
            ),
          );
        }
      }
    } else {
      List<Toilet> visibleToilets = [];
      for (final toilet in widget.toilets) {
        if (_visibleBounds != null) {
          final double latSpan =
              (_visibleBounds!.northeast.latitude -
                      _visibleBounds!.southwest.latitude)
                  .abs();
          final double lngSpan =
              (_visibleBounds!.northeast.longitude -
                      _visibleBounds!.southwest.longitude)
                  .abs();
          final double expandedSouth =
              _visibleBounds!.southwest.latitude - (latSpan * 0.2);
          final double expandedNorth =
              _visibleBounds!.northeast.latitude + (latSpan * 0.2);
          final double expandedWest =
              _visibleBounds!.southwest.longitude - (lngSpan * 0.2);
          final double expandedEast =
              _visibleBounds!.northeast.longitude + (lngSpan * 0.2);

          if (toilet.latitude < expandedSouth ||
              toilet.latitude > expandedNorth ||
              toilet.longitude < expandedWest ||
              toilet.longitude > expandedEast) {
            if (toilet.id != _visualSelectedToilet?.id) {
              continue;
            }
          }
        }
        visibleToilets.add(toilet);
      }

      LatLng? centerRef = _currentCameraPosition?.target;
      if (centerRef == null && _visibleBounds != null) {
        centerRef = LatLng(
          (_visibleBounds!.northeast.latitude +
                  _visibleBounds!.southwest.latitude) /
              2,
          (_visibleBounds!.northeast.longitude +
                  _visibleBounds!.southwest.longitude) /
              2,
        );
      }

      if (visibleToilets.length > 60 && centerRef != null) {
        final LatLng cr = centerRef;
        visibleToilets.sort((a, b) {
          if (a.id == _visualSelectedToilet?.id) return -1;
          if (b.id == _visualSelectedToilet?.id) return 1;

          final distA =
              pow(a.latitude - cr.latitude, 2) +
              pow(a.longitude - cr.longitude, 2);
          final distB =
              pow(b.latitude - cr.latitude, 2) +
              pow(b.longitude - cr.longitude, 2);
          return distA.compareTo(distB);
        });
        visibleToilets = visibleToilets.take(60).toList();
      }

      for (final toilet in visibleToilets) {
        final bool isSelected = toilet.id == _visualSelectedToilet?.id;
        markers.add(
          Marker(
            markerId: MarkerId(toilet.id),
            position: LatLng(toilet.latitude, toilet.longitude),
            icon: toiletMarkerIcon(toilet, isSelected),
            zIndexInt: isSelected ? 2 : 1,
            consumeTapEvents: true,
            onTap: () {
              CustomHapticsService.playSpringBounce();
              widget.onToiletSelected(toilet);
            },
          ),
        );
      }
    }
    _cachedMarkers = markers;
    return _cachedMarkers;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // PHYSICAL GLASS LISTENER: Kills the sensor instantly when skin touches screen
        Listener(
          onPointerDown: (_) {
            if (!_isUserInteracting) {
              setState(() {
                _isUserInteracting =
                    true; // Pauses background centering the moment the screen is touched
              });
            }
          },
          child: GoogleMap(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height < 600 ? 150.0 : 180.0,
            ),
            initialCameraPosition: const CameraPosition(
              target: LatLng(26.2940, 73.0185),
              zoom: 13.5,
            ),
            style: Theme.of(context).brightness == Brightness.light
                ? lightMapStyle
                : darkMapStyle,
            markers: _getMarkers(),
            onMapCreated: (controller) {
              _mapController = controller;
              widget.onMapCreated(controller);
              _startSensorStreams();
            },
            onCameraMoveStarted: () {
              if (!_isUserDraggingMap) {
                setState(() {
                  _isUserDraggingMap = true;
                });
              }
            },
            onCameraMove: (position) {
              _currentCameraPosition = position;
              _zoom = position.zoom;
            },
            onCameraIdle: () {
              if (mounted) {
                if (_isUserDraggingMap || _isAnimatingProgrammatically) {
                  setState(() {
                    _isUserDraggingMap = false;
                    _isAnimatingProgrammatically = false;
                  });
                }
              }
              if (mounted && _visualSelectedToilet != widget.selectedToilet) {
                setState(() {
                  _visualSelectedToilet = widget.selectedToilet;
                });
              }
              _mapController?.getVisibleRegion().then((b) {
                if (!mounted) return;
                final changed =
                    _visibleBounds == null ||
                    (b.southwest.latitude - _visibleBounds!.southwest.latitude)
                            .abs() >
                        0.0005 ||
                    (b.northeast.longitude -
                                _visibleBounds!.northeast.longitude)
                            .abs() >
                        0.0005;
                if (changed) setState(() => _visibleBounds = b);

                // Distance check for "Search this area"
                if (_currentCameraPosition != null) {
                  final target = _currentCameraPosition!.target;
                  final refLat =
                      widget.searchLat ?? widget.currentUserLatLng?.latitude;
                  final refLng =
                      widget.searchLng ?? widget.currentUserLatLng?.longitude;

                  if (refLat != null && refLng != null) {
                    final dist = Geolocator.distanceBetween(
                      refLat,
                      refLng,
                      target.latitude,
                      target.longitude,
                    );
                    if (dist > 3000.0 && !_showSearchThisArea) {
                      setState(() => _showSearchThisArea = true);
                    } else if (dist <= 3000.0 && _showSearchThisArea) {
                      setState(() => _showSearchThisArea = false);
                    }
                  }
                }
              });
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            tiltGesturesEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
          ),
        ),

        // SEARCH THIS AREA BUTTON
        if (_showSearchThisArea && widget.onSearchLocationUpdate != null)
          Positioned(
            top: 130.0,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    CustomHapticsService.playToggleSnap();
                    if (_currentCameraPosition != null) {
                      widget.onSearchLocationUpdate!(
                        "this area",
                        _currentCameraPosition!.target.latitude,
                        _currentCameraPosition!.target.longitude,
                      );
                      setState(() => _showSearchThisArea = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.sm.brandSolid,
                    foregroundColor: context.sm.onBrand,
                    elevation: 4.0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 12.0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24.0),
                    ),
                  ),
                  icon: const Icon(Icons.search, size: 18.0),
                  label: const Text(
                    "Search this area",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A map pin does NOT encode a live open/closed state or a quality grade.
///
/// condition evidence NO LONGER colours the pin. A one-account
/// majority ("1 check says closed") is honest as TEXT ("Recent checks: closed"
/// in the peek / list / detail), but a red map pin is a far stronger map-level
/// assertion and one account must not control it. Evidence-strength → visual
/// authority is GO's decision. In the current design every
/// mapped toilet is a NEUTRAL pin; it turns red only for an explicit, still-
/// valid moderation flag. No green "verified/open" treatment anywhere.
BitmapDescriptor toiletMarkerIcon(Toilet toilet, bool isSelected) {
  if (toilet.isFlagged) {
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  }
  return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
}
