import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/firestore_service.dart';
import '../widgets/evidence_status_label.dart';
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

  // honesty pass: the only filter kept is "Water listed" — it selects
  // toilets whose SOURCE positively listed water (`has_water == true`), which is
  // real positive evidence. "Open now" / "Free" / "Western" / "Women-safe" were
  // removed: with the current dataset they filter on importer defaults and
  // missing fields, turning "unknown" into a false "no".
  bool _filterOnlyWater = false;

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

  // Search is local-only: it filters `widget.toilets` (name + address) as you
  // type — see `displayedToilets` in build(). There is no place-lookup
  // network call here; to browse a different area, pan the map and use its
  // own "Search this area" control (see map_screen.dart), which re-centers
  // the query on the map's current viewport instead of a typed address.
  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query.toLowerCase().trim());
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) return;
    _addRecentSearch(query);
    _searchFocusNode.unfocus();
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

  // Icon comes from the identity-truth CONTEXT, not the raw `category` string
  // (base OSM rows are all hard-coded 'govt'). Unknown => a generic toilet pin.
  IconData _contextIcon(FacilityContext c) {
    switch (c) {
      case FacilityContext.petrolStation:
        return Icons.local_gas_station_outlined;
      case FacilityContext.commercial:
        return Icons.shopping_bag_outlined;
      case FacilityContext.station:
        return Icons.train_outlined;
      case FacilityContext.publicToilet:
      case FacilityContext.other:
      case FacilityContext.unknown:
        return Icons.wc_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Toilet> displayedToilets = widget.toilets.where((t) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        // Name + address only. The raw `category` is NOT searched — base OSM
        // rows are all hard-coded 'govt', so matching it would make every
        // imported toilet a false hit for "government".
        if (!t.name.toLowerCase().contains(q) &&
            !t.address.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_filterOnlyWater &&
          t.truth.amenities.water != EvidenceState.present) {
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
                  hintText: 'Search loaded toilets by name or address',
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

          // SEARCH MODE: recent searches dropdown
          if (widget.searchMode &&
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
                    label: 'Water listed',
                    icon: Icons.water_drop_outlined,
                    selected: _filterOnlyWater,
                    onTap: () =>
                        setState(() => _filterOnlyWater = !_filterOnlyWater),
                  ),
                ],
              ),
            ),

          Expanded(
            child: displayedToilets.isEmpty
                ? (_searchQuery.isNotEmpty || _filterOnlyWater
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
                        final pt = ToiletPresentation.fromEvidence(toilet);
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
                                    _contextIcon(pt.context),
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
                                        // Self-expiring: only a CURRENT
                                        // server-derived condition summary
                                        // (Evidence V2) moves this off "Status
                                        // unconfirmed", and it drops back when
                                        // the evidence window passes (no
                                        // polling).
                                        EvidenceStatusLabel(toilet),
                                        const SizedBox(width: SmTokens.s8),
                                        // Only a POSITIVE source/submitter
                                        // listing is shown (Truth V2); a stored
                                        // `false` / missing means "not
                                        // confirmed", not "no water".
                                        if (toilet.truth.amenities.water ==
                                            EvidenceState.present)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.water_drop_outlined,
                                                size: 14,
                                                color: context.sm.ink3,
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                'Water listed',
                                                style: SmText.caption.copyWith(
                                                  color: context.sm.ink3,
                                                ),
                                              ),
                                            ],
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
                                    // Ratings come from the SERVER-DERIVED
                                    // index (Evidence V2), never the frozen
                                    // parent aggregate. null => not indexed
                                    // (show nothing); "No ratings yet" => a
                                    // real indexed zero.
                                    if (pt.ratingsLabel != null) ...[
                                      const SizedBox(height: SmTokens.s4),
                                      Text(
                                        pt.ratingsLabel!,
                                        style: SmText.caption.copyWith(
                                          color: context.sm.ink3,
                                        ),
                                      ),
                                    ],
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
