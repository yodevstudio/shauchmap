import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';

import '../services/firestore_service.dart';
import '../services/places_service.dart';
import 'detail_sheet.dart';
import '../services/custom_haptics_service.dart';
import '../services/error_handler.dart';
import '../theme/sm_widgets.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../utils/format.dart';

class ListScreen extends StatefulWidget {
  final List<Toilet> toilets;
  final FirestoreService firestoreService;
  final bool isSignedIn;
  final String? userId;
  final String? userName;
  final VoidCallback onSignInRequest;
  final VoidCallback onRefreshToilets;
  final Position? userPosition;
  final String? viewingPlaceName;
  final void Function(String, double, double)? onSearchLocationUpdate;
  final VoidCallback? onClearSearch;
  final bool searchMode;

  const ListScreen({
    super.key,
    required this.toilets,
    required this.firestoreService,
    required this.isSignedIn,
    required this.userId,
    required this.userName,
    required this.onSignInRequest,
    required this.onRefreshToilets,
    this.userPosition,
    this.viewingPlaceName,
    this.onSearchLocationUpdate,
    this.onClearSearch,
    this.searchMode = false,
  });

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  final FocusNode _searchFocusNode = FocusNode();
  List<String> _recentSearches = [];

  final ScrollController _scrollController = ScrollController();
  int _displayLimit = 20;
  bool _isLoadingMore = false;

  bool _filterOnlyOpen = false;
  bool _filterOnlyFree = false;
  bool _filterOnlyWestern = false;
  bool _filterOnlyWater = false;
  bool _filterOnlyWomenSafe = false;

  @override
  void initState() {
    super.initState();
    if (widget.searchMode) _searchFocusNode.addListener(() => setState(() {}));
    _loadRecentSearches();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewingPlaceName != oldWidget.viewingPlaceName) {
      setState(() {
        _displayLimit = 20;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore &&
          _displayLimit < widget.toilets.length &&
          _searchQuery.isEmpty) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        _displayLimit += 10;
      });
    }
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  Future<void> _addRecentSearch(String term) async {
    if (term.trim().isEmpty) return;
    setState(() {
      _recentSearches.remove(term);
      _recentSearches.insert(0, term);
      if (_recentSearches.length > 5) _recentSearches.removeLast();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', _recentSearches);
  }

  Timer? _debounce;
  List<PlacePrediction> _predictions = [];

  // In-sheet place results (searchMode only)
  String? _viewingPlace;
  List<Toilet> _placeToilets = [];
  StreamSubscription<List<Toilet>>? _placeSub;
  bool _placeLoading = false;

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query.toLowerCase().trim());
    if (widget.onSearchLocationUpdate == null) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _predictions = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await PlacesService.getAutocomplete(query);
        if (mounted) {
          setState(() {
            _predictions = results;
          });
        }
      } catch (e) {
        // Handle error silently or log it
      }
    });
  }

  void _onPlaceSelected(PlacePrediction prediction) async {
    CustomHapticsService.playTileSelect();
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _predictions = [];
    });

    try {
      final loc = await PlacesService.getPlaceLocation(prediction.placeId);
      if (loc == null) return;
      _addRecentSearch(prediction.description);

      if (widget.searchMode) {
        // Stay in-sheet: load toilets for this place without recentering the map
        setState(() {
          _viewingPlace = prediction.description;
          _placeLoading = true;
          _placeToilets = [];
        });
        _placeSub?.cancel();
        _placeSub = widget.firestoreService
            .getToiletsNearby(
              latitude: loc.lat,
              longitude: loc.lng,
              radiusKm: 15.0,
            )
            .listen((list) {
              if (mounted) {
                setState(() {
                  _placeToilets = list;
                  _placeLoading = false;
                });
              }
            });
      } else if (widget.onSearchLocationUpdate != null) {
        widget.onSearchLocationUpdate!(
          prediction.description,
          loc.lat,
          loc.lng,
        );
      }
    } catch (e) {
      if (mounted) AppError.show(context, 'Failed to resolve location');
    }
  }

  void _clearPlaceResults() {
    _placeSub?.cancel();
    setState(() {
      _viewingPlace = null;
      _placeToilets = [];
      _placeLoading = false;
    });
    CustomHapticsService.playToggleSnap();
  }

  void _onSearchSubmitted(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final loc = await PlacesService.geocodeAddress(query);
      if (loc != null) {
        _addRecentSearch(query);
        CustomHapticsService.playTileSelect();
        _searchController.clear();
        setState(() {
          _searchQuery = '';
          _predictions = [];
        });
        _searchFocusNode.unfocus();

        if (widget.searchMode) {
          setState(() {
            _viewingPlace = query;
            _placeLoading = true;
            _placeToilets = [];
          });
          _placeSub?.cancel();
          _placeSub = widget.firestoreService
              .getToiletsNearby(
                latitude: loc.lat,
                longitude: loc.lng,
                radiusKm: 15.0,
              )
              .listen((list) {
                if (mounted) {
                  setState(() {
                    _placeToilets = list;
                    _placeLoading = false;
                  });
                }
              });
        } else if (widget.onSearchLocationUpdate != null) {
          widget.onSearchLocationUpdate!(query, loc.lat, loc.lng);
        }
      }
    } catch (e) {
      // Ignore
    }
  }

  void _startListening() async {
    if (!_isListening) {
      bool available = await _speechToText.initialize(
        onStatus: (val) {
          if (mounted && (val == 'done' || val == 'notListening')) {
            setState(() => _isListening = false);
          }
        },
        onError: (val) {
          if (mounted) {
            setState(() => _isListening = false);
            AppError.show(context, 'Speech error: ${val.errorMsg}');
          }
        },
      );
      if (available) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (val) {
            setState(() {
              _searchController.text = val.recognizedWords;
              _searchQuery = val.recognizedWords.toLowerCase().trim();
            });
            if (val.finalResult) {
              _onSearchSubmitted(val.recognizedWords);
            } else {
              _onSearchChanged(val.recognizedWords);
            }
          },
        );
      } else {
        if (mounted) {
          AppError.show(context, 'Speech recognition not available.');
        }
      }
    } else {
      setState(() => _isListening = false);
      _speechToText.stop();
    }
  }

  String? _getDistanceText(Toilet toilet) {
    if (widget.userPosition == null) return null;
    final double dist = Geolocator.distanceBetween(
      widget.userPosition!.latitude,
      widget.userPosition!.longitude,
      toilet.latitude,
      toilet.longitude,
    );
    return formatDistance(dist);
  }

  @override
  void dispose() {
    _speechToText.stop();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _placeSub?.cancel();
    _searchController.dispose();
    super.dispose();
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

  IconData _typeIcon(String category) {
    switch (category.toLowerCase()) {
      case 'petrol pump':
      case 'fuel':
        return Icons.local_gas_station_outlined;
      case 'mall':
      case 'shop':
      case 'commercial':
        return Icons.shopping_bag_outlined;
      case 'station':
      case 'railway':
        return Icons.train_outlined;
      default:
        return Icons.location_city_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    // When viewing a searched place in searchMode, use those toilets; otherwise use widget.toilets
    final List<Toilet> sourceToilets =
        (widget.searchMode && _viewingPlace != null)
        ? _placeToilets
        : widget.toilets;

    final List<Toilet> displayedToilets = sourceToilets.where((t) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!t.name.toLowerCase().contains(q) &&
            !t.address.toLowerCase().contains(q) &&
            !t.category.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_filterOnlyOpen && !t.isOpen) {
        return false;
      }
      if (_filterOnlyFree && !t.isFree) {
        return false;
      }
      if (_filterOnlyWestern && !t.isWestern) {
        return false;
      }
      if (_filterOnlyWater && !t.hasWater) {
        return false;
      }
      if (_filterOnlyWomenSafe && !t.isWomenSafe) {
        return false;
      }
      return true;
    }).toList();

    return Container(
      color: context.sm.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // SEARCH MODE: text field + mic
          if (widget.searchMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SmTokens.s16,
                SmTokens.s12,
                SmTokens.s16,
                SmTokens.s4,
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: SmText.body.copyWith(color: context.sm.ink),
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchSubmitted,
                decoration: InputDecoration(
                  hintText: 'Search by name or area...',
                  hintStyle: SmText.body.copyWith(color: context.sm.ink3),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: context.sm.ink3,
                    size: 20.0,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SmTokens.s8,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: context.sm.ink3,
                              size: 20.0,
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: _startListening,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: SmTokens.s12,
                            left: SmTokens.s4,
                          ),
                          child: Icon(
                            _isListening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            color: _isListening
                                ? context.sm.brand
                                : context.sm.ink3,
                            size: 20.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: context.sm.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: SmTokens.s16,
                    vertical: SmTokens.s12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SmTokens.rSmall),
                    borderSide: BorderSide(color: context.sm.line, width: 1.0),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SmTokens.rSmall),
                    borderSide: BorderSide(color: context.sm.line, width: 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SmTokens.rSmall),
                    borderSide: BorderSide(color: context.sm.line, width: 1.0),
                  ),
                ),
              ),
            ),

          // SEARCH MODE: "Viewing X ✕" banner when a place is selected
          if (widget.searchMode && _viewingPlace != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SmTokens.s16,
                SmTokens.s4,
                SmTokens.s16,
                SmTokens.s4,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SmTokens.s12,
                  vertical: SmTokens.s8,
                ),
                decoration: BoxDecoration(
                  color: context.sm.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(SmTokens.rSmall),
                  border: Border.all(
                    color: context.sm.brand.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: context.sm.brand, size: 14),
                    const SizedBox(width: SmTokens.s8),
                    Expanded(
                      child: Text(
                        'Viewing $_viewingPlace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SmText.caption.copyWith(
                          color: context.sm.brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearPlaceResults,
                      child: Padding(
                        padding: const EdgeInsets.only(left: SmTokens.s8),
                        child: Icon(
                          Icons.close_rounded,
                          color: context.sm.brand,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // SEARCH MODE: loading indicator for place toilets
          if (widget.searchMode && _placeLoading)
            Padding(
              padding: const EdgeInsets.all(SmTokens.s24),
              child: Center(
                child: CircularProgressIndicator(
                  color: context.sm.brandSolid,
                  strokeWidth: 2,
                ),
              ),
            ),

          // SEARCH MODE: recent searches dropdown
          if (widget.searchMode &&
              _viewingPlace == null &&
              _searchFocusNode.hasFocus &&
              _searchQuery.isEmpty &&
              _recentSearches.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: SmTokens.s16,
                vertical: SmTokens.s4,
              ),
              child: SmCard(
                padding: EdgeInsets.zero,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentSearches.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: context.sm.line, height: 1.0),
                  itemBuilder: (context, index) {
                    final term = _recentSearches[index];
                    return ListTile(
                      leading: Icon(Icons.history, color: context.sm.ink3),
                      title: Text(
                        term,
                        style: SmText.body.copyWith(color: context.sm.ink),
                      ),
                      onTap: () {
                        _searchController.text = term;
                        _onSearchChanged(term);
                        _onSearchSubmitted(term);
                        _searchFocusNode.unfocus();
                      },
                    );
                  },
                ),
              ),
            )
          // SEARCH MODE: autocomplete predictions
          else if (widget.searchMode &&
              _viewingPlace == null &&
              _predictions.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: SmTokens.s16,
                vertical: SmTokens.s4,
              ),
              child: SmCard(
                padding: EdgeInsets.zero,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _predictions.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: context.sm.line, height: 1.0),
                  itemBuilder: (context, index) {
                    final p = _predictions[index];
                    return ListTile(
                      leading: Icon(Icons.location_on, color: context.sm.brand),
                      title: Text(
                        p.description,
                        style: SmText.body.copyWith(color: context.sm.ink),
                      ),
                      onTap: () => _onPlaceSelected(p),
                    );
                  },
                ),
              ),
            ),

          // BROWSE MODE: header
          if (!widget.searchMode)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SmTokens.s24,
                vertical: SmTokens.s16,
              ),
              color: context.sm.bg,
              child: Text(
                "${widget.viewingPlaceName ?? 'Nearby'} \u00B7 ${displayedToilets.length} toilets",
                style: SmText.title.copyWith(color: context.sm.ink),
              ),
            ),

          // BROWSE MODE: viewingPlaceName banner
          if (!widget.searchMode && widget.viewingPlaceName != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SmTokens.s16,
                vertical: SmTokens.s8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SmTokens.s12,
                        vertical: SmTokens.s8,
                      ),
                      decoration: BoxDecoration(
                        color: context.sm.brand.withValues(alpha: 0.15),
                        border: Border.all(
                          color: context.sm.brand.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(SmTokens.s8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'Viewing ${widget.viewingPlaceName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.sm.brand,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              CustomHapticsService.playToggleSnap();
                              widget.onClearSearch?.call();
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(left: SmTokens.s8),
                              child: Icon(
                                Icons.close,
                                color: context.sm.brand,
                                size: 16.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // BROWSE MODE: filter chips
          if (!widget.searchMode)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: SmTokens.s16,
                vertical: SmTokens.s8,
              ),
              child: Row(
                children: [
                  SmFilterChip(
                    label: 'Open now',
                    selected: _filterOnlyOpen,
                    onTap: () =>
                        setState(() => _filterOnlyOpen = !_filterOnlyOpen),
                  ),
                  const SizedBox(width: SmTokens.s8),
                  SmFilterChip(
                    label: 'Free',
                    selected: _filterOnlyFree,
                    onTap: () =>
                        setState(() => _filterOnlyFree = !_filterOnlyFree),
                  ),
                  const SizedBox(width: SmTokens.s8),
                  SmFilterChip(
                    label: 'Western',
                    selected: _filterOnlyWestern,
                    onTap: () => setState(
                      () => _filterOnlyWestern = !_filterOnlyWestern,
                    ),
                  ),
                  const SizedBox(width: SmTokens.s8),
                  SmFilterChip(
                    label: 'Has water',
                    selected: _filterOnlyWater,
                    onTap: () =>
                        setState(() => _filterOnlyWater = !_filterOnlyWater),
                  ),
                  const SizedBox(width: SmTokens.s8),
                  SmFilterChip(
                    label: 'Women-safe',
                    selected: _filterOnlyWomenSafe,
                    onTap: () => setState(
                      () => _filterOnlyWomenSafe = !_filterOnlyWomenSafe,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: displayedToilets.isEmpty
                ? (_searchQuery.isNotEmpty ||
                          _filterOnlyOpen ||
                          _filterOnlyFree ||
                          _filterOnlyWestern ||
                          _filterOnlyWater ||
                          _filterOnlyWomenSafe
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off,
                                color: context.sm.ink3,
                                size: 48.0,
                              ),
                              const SizedBox(height: SmTokens.s16),
                              Text(
                                "No results found",
                                style: SmText.title.copyWith(
                                  color: context.sm.ink,
                                ),
                              ),
                              const SizedBox(height: SmTokens.s8),
                              Text(
                                'We couldn\'t find anything matching your filters.',
                                style: SmText.body.copyWith(
                                  color: context.sm.ink3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : widget.toilets.isEmpty
                      ? Shimmer.fromColors(
                          baseColor: context.sm.soft,
                          highlightColor: context.sm.surface,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(SmTokens.s24),
                            itemCount: 4,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: SmTokens.s12),
                            itemBuilder: (context, index) => Container(
                              height: 88.0,
                              decoration: BoxDecoration(
                                color: context.sm.surface,
                                borderRadius: BorderRadius.circular(
                                  SmTokens.rCard,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                color: context.sm.brand,
                                size: 48.0,
                              ),
                              const SizedBox(height: SmTokens.s16),
                              Text(
                                "No toilets here",
                                style: SmText.title.copyWith(
                                  color: context.sm.ink,
                                ),
                              ),
                              const SizedBox(height: SmTokens.s8),
                              Text(
                                "Try panning the map or clearing your search.",
                                style: SmText.body.copyWith(
                                  color: context.sm.ink3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ))
                : RefreshIndicator(
                    color: context.sm.brand,
                    backgroundColor: context.sm.bg,
                    onRefresh: () async {
                      widget.onRefreshToilets();
                      await Future.delayed(const Duration(milliseconds: 800));
                    },
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(SmTokens.s24),
                      itemCount: displayedToilets.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: SmTokens.s12),
                      itemBuilder: (context, index) {
                        final toilet = displayedToilets[index];
                        return SmCard(
                          onTap: () {
                            CustomHapticsService.playTileSelect();
                            _openDetailSheet(toilet);
                          },
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: context.sm.soft,
                                  borderRadius: BorderRadius.circular(
                                    SmTokens.rSmall,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    _typeIcon(toilet.category),
                                    color: context.sm.ink2,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: SmTokens.s12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      toilet.name,
                                      style: SmText.bodyStrong.copyWith(
                                        color: context.sm.ink,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: SmTokens.s4),
                                    Row(
                                      children: [
                                        SmStatusLabel(
                                          toilet.isOpen
                                              ? SmStatus.open
                                              : SmStatus.closed,
                                          text: toilet.isOpen
                                              ? 'Open'
                                              : 'Closed',
                                        ),
                                        const SizedBox(width: SmTokens.s8),
                                        if (toilet.hasWater)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: SmTokens.s4,
                                            ),
                                            child: Icon(
                                              Icons.water_drop_outlined,
                                              size: 14,
                                              color: context.sm.ink3,
                                            ),
                                          ),
                                        if (toilet.isFree)
                                          Icon(
                                            Icons.money_off_outlined,
                                            size: 14,
                                            color: context.sm.ink3,
                                          ),
                                      ],
                                    ),
                                    if (toilet.landmark.isNotEmpty) ...[
                                      const SizedBox(height: SmTokens.s4),
                                      Text(
                                        toilet.landmark,
                                        style: SmText.caption.copyWith(
                                          color: context.sm.ink3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: SmTokens.s4),
                                    if (toilet.starRating > 0)
                                      Text(
                                        '\u2605 ${toilet.starRating.toStringAsFixed(1)}',
                                        style: SmText.caption.copyWith(
                                          color: context.sm.star,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    else
                                      Text(
                                        'Not rated \u00B7 be the first +10 XP',
                                        style: SmText.caption.copyWith(
                                          color: context.sm.brand,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: SmTokens.s12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _getDistanceText(toilet) ?? 'Unknown',
                                    style: SmText.bodyStrong.copyWith(
                                      color: context.sm.ink,
                                    ),
                                  ),
                                  Text(
                                    'away',
                                    style: SmText.caption.copyWith(
                                      color: context.sm.ink3,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
