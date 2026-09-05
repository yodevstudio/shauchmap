import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../services/firestore_service.dart';
import '../services/custom_haptics_service.dart';
import '../utils/map_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'quick_check_sheet.dart';

import 'rating_sheet.dart';
import '../main.dart';

import '../services/feedback_bus.dart' as fbus;

import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';
import '../widgets/travel_mode_sheet.dart';

class DetailSheet extends StatefulWidget {
  final Toilet toilet;
  final Position? userPosition;
  final bool isSignedIn;
  final String? userId;
  final String? userName;
  final VoidCallback onSignInRequest;
  final VoidCallback onRefreshToilets;

  const DetailSheet({
    super.key,
    required this.toilet,
    this.userPosition,
    required this.isSignedIn,
    required this.userId,
    required this.userName,
    required this.onSignInRequest,
    required this.onRefreshToilets,
  });

  @override
  State<DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<DetailSheet>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  bool? _userVote;
  bool _checkInLoading = false;
  bool _isBookmarkAnimating = false;
  bool _isActionProcessing = false;
  bool? _localIsSaved;
  late final Stream<List<Map<String, dynamic>>> _ratingsStream;

  // PASSIVE EXPIRY : the condition StreamBuilder gets no new event just
  // because 60 minutes elapsed, so a one-shot Timer (no polling) forces ONE
  // rebuild at the direct summary's conservative `validUntilMs`, after which
  // the verdict drops to UNKNOWN until a fresh Firestore snapshot recomputes it.
  Timer? _condExpiryTimer;
  int? _condExpiryScheduledMs;

  void _scheduleConditionExpiry(int? validUntilMs) {
    if (validUntilMs == _condExpiryScheduledMs) return;
    _condExpiryScheduledMs = validUntilMs;
    _condExpiryTimer?.cancel();
    _condExpiryTimer = null;
    if (validUntilMs == null) return;
    final d =
        DateTime.fromMillisecondsSinceEpoch(
          validUntilMs,
        ).difference(DateTime.now()) +
        const Duration(milliseconds: 50);
    if (d.isNegative) return;
    _condExpiryTimer = Timer(d, () {
      if (mounted) setState(() {});
    });
  }

  // Read-time aggregates (2026-09-02 trust model): computed by Firestore from
  // the owner-scoped sub-collections (one doc per account), NOT read off a
  // client-writable parent field. Null until loaded / on query failure —
  // a failed query is NOT the same as "zero", so the UI omits the figure
  // rather than showing a fabricated 0.
  ({int count, double average})? _ratingSummary;

  // Vote aggregate availability. Vote docs are readable only to SIGNED-IN
  // accounts, so getVoteSummary() fails for signed-out viewers. null/false =>
  // the thumbs row shows "—", NOT the frozen parent 0/0 as if it were real.
  // Set true once we have a real derived count OR the user has cast a vote
  // (their optimistic local count is then at least their own truth).
  bool? _voteAggOk;

  // Animation for +20 XP floating badge
  late AnimationController _badgeController;
  late Animation<double> _badgeOpacity;
  late Animation<double> _badgeSlide;
  bool _showBadge = false;

  @override
  void initState() {
    super.initState();
    _ratingsStream = _firestoreService
        .getRecentRatingsStream(widget.toilet.id)
        .asBroadcastStream();

    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _badgeOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20.0,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 60.0),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 20.0,
      ),
    ]).animate(_badgeController);

    _badgeSlide = Tween<double>(
      begin: 0.0,
      end: -60.0,
    ).animate(CurvedAnimation(parent: _badgeController, curve: Curves.easeOut));

    if (widget.isSignedIn && widget.userId != null) {
      _firestoreService
          .getUserVote(widget.toilet.id, widget.userId!)
          .then((v) {
            if (mounted) setState(() => _userVote = v);
          })
          .catchError((_) {});
    }

    _loadAggregates();
  }

  Future<void> _loadAggregates() async {
    final rating = await _firestoreService.getRatingSummary(widget.toilet.id);
    final votes = await _firestoreService.getVoteSummary(widget.toilet.id);
    if (!mounted) return;
    setState(() {
      // A failed aggregation query is "unavailable", not "zero": leave the
      // figure unset / the model counters untouched rather than paint a 0.
      _ratingSummary = rating.ok
          ? (count: rating.count, average: rating.average)
          : null;
      _voteAggOk = votes.ok;
      if (votes.ok) {
        widget.toilet.upvoteCount = votes.up;
        widget.toilet.downvoteCount = votes.down;
      } else {
        debugPrint(
          'DetailSheet: vote summary unavailable (signed-out, or query '
          'failed) — thumbs row shows "—", not a fabricated 0.',
        );
      }
    });
  }

  @override
  void dispose() {
    _condExpiryTimer?.cancel();
    _badgeController.dispose();
    super.dispose();
  }

  Widget _voteBtn({required bool up}) {
    final c = context.sm;
    final active = _userVote == up;
    final accent = up ? c.statusOpen : c.statusClosed;
    // "—" until we have a real derived count (or the viewer has voted). Never
    // present the frozen parent 0/0 as a genuine aggregate.
    final String countLabel = _voteAggOk == true
        ? '${up ? widget.toilet.upvoteCount : widget.toilet.downvoteCount}'
        : '—';
    return GestureDetector(
      onTap: () => _handleVote(up),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: SmTokens.s12,
          vertical: SmTokens.s8,
        ),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : c.soft,
          borderRadius: BorderRadius.circular(SmTokens.rPill),
          border: Border.all(color: active ? accent : c.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
              size: 15,
              color: active ? accent : c.ink3,
            ),
            const SizedBox(width: SmTokens.s4),
            Text(
              countLabel,
              style: SmText.caption.copyWith(
                color: active ? accent : c.ink3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performCheckIn() async {
    if (!widget.isSignedIn || widget.userId == null) {
      widget.onSignInRequest();
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _checkInLoading = true;
    });
    try {
      final success = await _firestoreService.checkIn(
        widget.toilet.id,
        widget.userId!,
      );
      if (success) {
        fbus.Feedback.fire(fbus.FeedbackEvent.reward);
        showAppSnackBar('Checked in!');
        if (mounted) {
          setState(() => _showBadge = true);
          _badgeController.forward();
        }
      } else {
        fbus.Feedback.fire(fbus.FeedbackEvent.error);
        showAppSnackBar('You already checked in here recently.', isError: true);
      }
    } catch (_) {
      fbus.Feedback.fire(fbus.FeedbackEvent.error);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _checkInLoading = false;
    });
  }

  Future<void> _handleVote(bool isUpvote) async {
    if (!widget.isSignedIn || widget.userId == null) {
      widget.onSignInRequest();
      return;
    }
    if (_isActionProcessing) {
      return;
    }
    final bool? prevVote = _userVote;
    final bool? newVote = prevVote == isUpvote ? null : isUpvote;

    if (!mounted) {
      return;
    }
    setState(() {
      _isActionProcessing = true;
      _userVote = newVote;
      // The viewer is signed-in and voting; from here the local counters
      // reflect at least their own vote, so a real number is honest to show.
      _voteAggOk = true;
      if (newVote == null) {
        if (prevVote == true) {
          widget.toilet.upvoteCount = (widget.toilet.upvoteCount - 1).clamp(
            0,
            999999,
          );
        }
        if (prevVote == false) {
          widget.toilet.downvoteCount = (widget.toilet.downvoteCount - 1).clamp(
            0,
            999999,
          );
        }
      } else {
        if (isUpvote) {
          widget.toilet.upvoteCount += 1;
          if (prevVote == false) {
            widget.toilet.downvoteCount = (widget.toilet.downvoteCount - 1)
                .clamp(0, 999999);
          }
        } else {
          widget.toilet.downvoteCount += 1;
          if (prevVote == true) {
            widget.toilet.upvoteCount = (widget.toilet.upvoteCount - 1).clamp(
              0,
              999999,
            );
          }
        }
      }
    });

    try {
      await _firestoreService.voteToilet(
        widget.toilet.id,
        widget.userId!,
        newVote,
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar("Vote failed: $e", isError: true);
        setState(() {
          _userVote = prevVote;
          if (newVote == null) {
            if (prevVote == true) widget.toilet.upvoteCount += 1;
            if (prevVote == false) widget.toilet.downvoteCount += 1;
          } else {
            if (isUpvote) {
              widget.toilet.upvoteCount = (widget.toilet.upvoteCount - 1).clamp(
                0,
                999999,
              );
              if (prevVote == false) widget.toilet.downvoteCount += 1;
            } else {
              widget.toilet.downvoteCount = (widget.toilet.downvoteCount - 1)
                  .clamp(0, 999999);
              if (prevVote == true) widget.toilet.upvoteCount += 1;
            }
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }

  void _shareToilet() {
    final rs = _ratingSummary;
    final String starLine = (rs != null && rs.count > 0)
        ? "\n⭐ ${rs.average.toStringAsFixed(1)} (${rs.count} rating${rs.count == 1 ? '' : 's'})"
        : "";
    Share.share(
      "📍 ${widget.toilet.name.replaceAll('\n', ' ')}$starLine\n🚶 ${widget.toilet.address}\n\nView and navigate on ShauchMap.",
    );
  }

  Future<void> _toggleSave(bool isSaved) async {
    if (!widget.isSignedIn || widget.userId == null) {
      widget.onSignInRequest();
      return;
    }
    if (_isActionProcessing) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isActionProcessing = true;
      _localIsSaved = !isSaved;
      _isBookmarkAnimating = true;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) {
        return;
      }
      setState(() => _isBookmarkAnimating = false);
    });

    try {
      if (isSaved) {
        await _firestoreService.unsaveToilet(widget.userId!, widget.toilet.id);
      } else {
        await _firestoreService.saveToilet(widget.userId!, widget.toilet.id);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar("Error: $e", isError: true);
        if (!mounted) {
          return;
        }
        setState(() => _localIsSaved = isSaved);
      }
    } finally {
      if (mounted) setState(() => _isActionProcessing = false);
    }
  }

  void _openQuickCheckSheet() {
    if (!widget.isSignedIn || widget.userId == null) {
      widget.onSignInRequest();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuickCheckSheet(
        toilet: widget.toilet,
        userId: widget.userId!,
        userName: widget.userName ?? '',
      ),
    ).then((_) => _loadAggregates());
  }

  void _openRatingSheet() {
    if (!widget.isSignedIn || widget.userId == null) {
      widget.onSignInRequest();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RatingSheet(
        toilet: widget.toilet,
        userId: widget.userId,
        userName: widget.userName,
        onSubmitted: widget.onRefreshToilets,
      ),
    ).then((_) => _loadAggregates());
  }

  @override
  Widget build(BuildContext context) {
    // Presentation Truth : never trust the imported `is_open` /
    // `is_free` / amenity booleans as live fact. Live status comes only from
    // the condition-check StreamBuilder below; here we show "Status
    // unconfirmed" until that stream says otherwise.
    final truth = ToiletPresentation.fromToilet(widget.toilet);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: smSheetDecoration(context),
          padding: const EdgeInsets.only(top: SmTokens.s12),
          child: Column(
            children: [
              // 1. Grab handle
              const SmGrabHandle(),
              const SizedBox(height: SmTokens.s12),

              // Scrollable Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: SmTokens.s24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 2. Photo placeholder
                      SmCard(
                        padding: const EdgeInsets.all(SmTokens.s16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              color: context.sm.ink3,
                              size: 20,
                            ),
                            const SizedBox(width: SmTokens.s8),
                            Text(
                              'Photos arrive in v1.1',
                              style: SmText.body.copyWith(
                                color: context.sm.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 3. Toilet name
                      const SizedBox(height: SmTokens.s20),
                      Hero(
                        tag: 'toilet_name_${widget.toilet.id}',
                        child: Material(
                          color: Colors.transparent,
                          child: Text(
                            widget.toilet.name.replaceAll('\n', ' '),
                            style: SmText.title.copyWith(color: context.sm.ink),
                          ),
                        ),
                      ),

                      // 4. Meta row
                      const SizedBox(height: SmTokens.s8),
                      Wrap(
                        spacing: SmTokens.s8,
                        runSpacing: SmTokens.s8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Classification comes from the identity-truth layer,
                          // NEVER the raw `category` string (base OSM rows are
                          // all hard-coded 'govt'). Unknown => "Mapped toilet".
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 14,
                                color: context.sm.ink3,
                              ),
                              const SizedBox(width: SmTokens.s4),
                              Text(
                                truth.contextLabel.toUpperCase(),
                                style: SmText.caption.copyWith(
                                  color: context.sm.ink2,
                                ),
                              ),
                            ],
                          ),
                          if (truth.genderLabel != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 14,
                                  color: context.sm.ink3,
                                ),
                                const SizedBox(width: SmTokens.s4),
                                Text(
                                  truth.genderLabel!.toUpperCase(),
                                  style: SmText.caption.copyWith(
                                    color: context.sm.ink2,
                                  ),
                                ),
                              ],
                            ),
                          if (truth.isCandidate)
                            SmFilterChip(
                              label: 'Unconfirmed location',
                              icon: Icons.help_outline,
                              selected: false,
                              onTap: () {},
                            ),
                          SmFilterChip(
                            label: truth.feeLabel,
                            selected: false,
                            onTap: () {},
                          ),
                          // Imported `is_open` is an importer default, not an
                          // observation — the live status card below is the
                          // only place a real Open/Closed is shown.
                          SmStatusLabel(
                            SmStatus.unsure,
                            text: 'Status unconfirmed',
                          ),
                        ],
                      ),

                      // 5. Landmark line
                      if (widget.toilet.landmark.isNotEmpty) ...[
                        const SizedBox(height: SmTokens.s8),
                        Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: context.sm.ink3,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                widget.toilet.landmark,
                                style: SmText.body.copyWith(
                                  color: context.sm.ink2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: SmTokens.s20),

                      // 6. Condition card — honest, read-time. Says only what
                      // the recent condition checks actually support; "no
                      // recent checks" is stated plainly, never a fake score.
                      StreamBuilder<Map<String, dynamic>>(
                        stream: _firestoreService.getConditionSummary(
                          widget.toilet.id,
                        ),
                        builder: (context, snap) {
                          final c = context.sm;
                          final data = snap.data;
                          final DateTime now = DateTime.now();
                          // The LIVE direct query is the high-fidelity source
                          // for the ONE open toilet (it reads the full
                          // one-doc-per-account collection, no limit). If it
                          // fails, fall back to a CURRENT server-derived
                          // Evidence V2 summary — never to "zero".
                          final bool rawFailed =
                              snap.hasError ||
                              snap.connectionState == ConnectionState.none;

                          int count;
                          String usable;
                          String open;
                          int minutesAgo;
                          bool unavailable = false;
                          bool fromIndex = false;
                          bool expired = false;

                          if (!rawFailed) {
                            count = (data?['count'] as int?) ?? 0;
                            usable = (data?['usable'] as String?) ?? 'unknown';
                            open = (data?['open'] as String?) ?? 'unknown';
                            minutesAgo = (data?['minutesAgo'] as int?) ?? 0;
                            final int? vum = data?['validUntilMs'] as int?;
                            // Schedule one rebuild at the window's edge.
                            _scheduleConditionExpiry(count > 0 ? vum : null);
                            // PASSIVE EXPIRY: if wall-clock has passed the
                            // conservative window with no fresh snapshot, drop
                            // the verdict to UNKNOWN.
                            if (count > 0 &&
                                vum != null &&
                                now.millisecondsSinceEpoch >= vum) {
                              expired = true;
                              usable = 'unknown';
                              open = 'unknown';
                            }
                          } else {
                            _scheduleConditionExpiry(null);
                            final ce = widget.toilet.evidence.condition;
                            if (ce.isCurrentlyValid(now)) {
                              fromIndex = true;
                              count = ce.contributorCount;
                              usable = ce.usable.name; // yes | no | unknown
                              open = ce.open.name;
                              minutesAgo = ce.ageMinutes(now) ?? 0;
                            } else {
                              unavailable = true;
                              count = 0;
                              usable = 'unknown';
                              open = 'unknown';
                              minutesAgo = 0;
                            }
                          }

                          IconData icon;
                          Color color;
                          String title;
                          if (unavailable) {
                            icon = Icons.cloud_off_outlined;
                            color = c.ink3;
                            title = 'Condition status unavailable';
                          } else if (expired) {
                            icon = Icons.hourglass_empty;
                            color = c.ink3;
                            title = 'Condition unconfirmed';
                          } else if (count == 0) {
                            icon = Icons.help_outline;
                            color = c.ink3;
                            title = 'Condition unconfirmed';
                          } else if (usable == 'no' || open == 'no') {
                            icon = Icons.error_outline;
                            color = c.statusClosed;
                            title = 'Recent checks: not usable';
                          } else if (usable == 'yes') {
                            icon = Icons.check_circle_outline;
                            color = c.statusOpen;
                            title = 'Recent checks: usable';
                          } else {
                            icon = Icons.help_outline;
                            color = c.statusUnsure;
                            title = 'Mixed / unconfirmed';
                          }

                          final String sub = unavailable
                              ? 'Could not reach the condition history. This is not the same as "no checks".'
                              : expired
                              ? 'The last condition checks have aged past the 1-hour window. Tap "Condition check" to refresh.'
                              : count == 0
                              ? 'No condition checks in the last hour. Tap "Condition check" to add one.'
                              : fromIndex
                              ? 'From recent condition checks (server index) · $count contributor${count == 1 ? '' : 's'} · $minutesAgo min ago'
                              : '$count check${count == 1 ? '' : 's'} in the last hour · last $minutesAgo min ago';

                          return SmCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(icon, color: color, size: 18),
                                    const SizedBox(width: SmTokens.s8),
                                    Text(
                                      title,
                                      style: SmText.bodyStrong.copyWith(
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: SmTokens.s4),
                                Text(
                                  sub,
                                  style: SmText.caption.copyWith(color: c.ink2),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: SmTokens.s20),

                      // Thumbs vote row
                      Padding(
                        padding: const EdgeInsets.only(bottom: SmTokens.s12),
                        child: Row(
                          children: [
                            _voteBtn(up: true),
                            const SizedBox(width: SmTokens.s8),
                            _voteBtn(up: false),
                            const Spacer(),
                            Text(
                              'was it usable?',
                              style: SmText.caption.copyWith(
                                color: context.sm.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 7. Actions row (Check-in, Rate, Save, Share)
                      Builder(
                        builder: (context) {
                          final c = context.sm;
                          Widget chip({
                            required IconData icon,
                            required String label,
                            required VoidCallback? onTap,
                            Widget? iconOverride,
                          }) {
                            return Expanded(
                              child: GestureDetector(
                                onTap: onTap,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: SmTokens.s12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.surface,
                                    borderRadius: BorderRadius.circular(
                                      SmTokens.rSmall,
                                    ),
                                    border: Border.all(color: c.line, width: 1),
                                    boxShadow: context.smSoft,
                                  ),
                                  child: Column(
                                    children: [
                                      iconOverride ??
                                          Icon(icon, color: c.brand, size: 22),
                                      const SizedBox(height: SmTokens.s4),
                                      Text(
                                        label,
                                        style: SmText.caption.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          return Row(
                            children: [
                              chip(
                                icon: Icons.thumb_up_outlined,
                                label: 'Check in',
                                onTap: _checkInLoading ? null : _performCheckIn,
                                iconOverride: _checkInLoading
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: c.brand,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: SmTokens.s8),
                              chip(
                                icon: Icons.star_outline_rounded,
                                label: 'Rate',
                                onTap: _openRatingSheet,
                              ),
                              const SizedBox(width: SmTokens.s8),
                              StreamBuilder<DocumentSnapshot>(
                                stream: widget.userId != null
                                    ? _firestoreService.getUserStream(
                                        widget.userId!,
                                      )
                                    : null,
                                builder: (context, snapshot) {
                                  bool isSaved = false;
                                  if (snapshot.hasData &&
                                      snapshot.data!.exists) {
                                    final data =
                                        snapshot.data!.data()
                                            as Map<String, dynamic>?;
                                    if (data != null) {
                                      final List<dynamic> saved =
                                          data['saved_toilets'] ?? [];
                                      isSaved = saved.contains(
                                        widget.toilet.id,
                                      );
                                    }
                                  }
                                  if (_localIsSaved != null) {
                                    isSaved = _localIsSaved!;
                                  }
                                  return chip(
                                    icon: Icons.bookmark_outline,
                                    label: 'Save',
                                    onTap: () => _toggleSave(isSaved),
                                    iconOverride: AnimatedScale(
                                      scale: _isBookmarkAnimating ? 1.2 : 1.0,
                                      duration: const Duration(
                                        milliseconds: 100,
                                      ),
                                      child: Icon(
                                        isSaved
                                            ? Icons.bookmark
                                            : Icons.bookmark_outline,
                                        color: c.brand,
                                        size: 22,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: SmTokens.s8),
                              chip(
                                icon: Icons.share_outlined,
                                label: 'Share',
                                onTap: _shareToilet,
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: SmTokens.s12),

                      // Report a problem
                      Center(
                        child: TextButton(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: context.sm.bg,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16.0),
                                ),
                              ),
                              builder: (sheetContext) {
                                return SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 8.0),
                                      const SmGrabHandle(),
                                      const SizedBox(height: 12.0),
                                      for (final reason in [
                                        'Closed permanently',
                                        'Wrong location',
                                        "Doesn't exist",
                                        'Inappropriate',
                                      ])
                                        ListTile(
                                          title: Text(
                                            reason,
                                            style: SmText.body.copyWith(
                                              color: context.sm.ink,
                                            ),
                                          ),
                                          onTap: () async {
                                            Navigator.of(sheetContext).pop();
                                            if (widget.userId == null) {
                                              widget.onSignInRequest();
                                              return;
                                            }
                                            try {
                                              await _firestoreService
                                                  .reportToilet(
                                                    widget.toilet.id,
                                                    widget.userId!,
                                                    reason,
                                                  );
                                              showAppSnackBar(
                                                "Thanks. Your report was recorded.",
                                              );
                                            } catch (_) {
                                              showAppSnackBar(
                                                "Something went wrong. Please try again.",
                                                isError: true,
                                              );
                                            }
                                          },
                                        ),
                                      const SizedBox(height: 8.0),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          child: Text(
                            'Report a problem',
                            style: SmText.caption.copyWith(
                              color: context.sm.ink3,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: SmTokens.s20),

                      // 8. Amenities section — Presentation Truth .
                      // Legacy/imported data cannot distinguish "source said
                      // no" from "source did not say", so a stored `false` is
                      // shown as "Unknown", never a confident "No". A stored
                      // `true` is "Listed" (source-reported), not "verified
                      // now".
                      SmEyebrow('What\'s inside'),
                      const SizedBox(height: SmTokens.s8),
                      Builder(
                        builder: (context) {
                          String amenity(AmenityEvidence e) => switch (e) {
                            AmenityEvidence.listed => 'Listed',
                            AmenityEvidence.notPresent => 'Not present',
                            AmenityEvidence.unknown => 'Unknown',
                          };
                          Widget div() =>
                              Divider(color: context.sm.surface, height: 1);
                          return SmCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                SmAmenityValue(
                                  label: 'Water facility',
                                  icon: Icons.water_drop_outlined,
                                  value: null,
                                  valueText: amenity(truth.water),
                                ),
                                div(),
                                SmAmenityValue(
                                  label: 'Soap',
                                  icon: Icons.soap_outlined,
                                  value: null,
                                  valueText: amenity(truth.soap),
                                ),
                                div(),
                                SmAmenityValue(
                                  label: 'Door / lock',
                                  icon: Icons.lock_outlined,
                                  value: null,
                                  valueText: amenity(truth.lock),
                                ),
                                div(),
                                SmAmenityValue(
                                  label: 'Western seat',
                                  icon: Icons.event_seat_outlined,
                                  value: null,
                                  valueText: amenity(truth.western),
                                ),
                                div(),
                                SmAmenityValue(
                                  label: 'Wheelchair access',
                                  icon: Icons.accessible_outlined,
                                  value: null,
                                  valueText: amenity(truth.wheelchair),
                                ),
                                div(),
                                SmAmenityValue(
                                  label: 'Baby changing',
                                  icon: Icons.baby_changing_station,
                                  value: null,
                                  valueText: amenity(truth.babyChange),
                                ),
                                div(),
                                SmAmenityValue(
                                  label: 'Sanitary disposal',
                                  icon: Icons.delete_outline,
                                  value: null,
                                  valueText: amenity(truth.sanitaryDisposal),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: SmTokens.s20),

                      // Live Status — tri-state condition checks in the last
                      // hour. 'unknown' is shown honestly as "Not sure"; a
                      // single old check never asserts a status.
                      SmEyebrow('Live Status'),
                      const SizedBox(height: SmTokens.s8),
                      StreamBuilder<Map<String, dynamic>>(
                        stream: _firestoreService.getConditionSummary(
                          widget.toilet.id,
                        ),
                        builder: (context, snapshot) {
                          final data = snapshot.data;
                          final bool unavailable =
                              snapshot.hasError ||
                              snapshot.connectionState == ConnectionState.none;
                          final int count = (data?['count'] as int?) ?? 0;
                          if (unavailable) {
                            return SmCard(
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cloud_off_outlined,
                                    color: context.sm.ink3,
                                    size: 20,
                                  ),
                                  const SizedBox(width: SmTokens.s8),
                                  Expanded(
                                    child: Text(
                                      "Condition history unavailable — not the "
                                      "same as no checks.",
                                      style: SmText.body.copyWith(
                                        color: context.sm.ink2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (count == 0) {
                            return SmCard(
                              onTap: _openQuickCheckSheet,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.help_outline,
                                    color: context.sm.ink3,
                                    size: 20,
                                  ),
                                  const SizedBox(width: SmTokens.s8),
                                  Expanded(
                                    child: Text(
                                      "No recent condition checks.",
                                      style: SmText.body.copyWith(
                                        color: context.sm.ink2,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "Check now",
                                    style: SmText.bodyStrong.copyWith(
                                      color: context.sm.brand,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          bool? tri(String? v) =>
                              v == 'yes' ? true : (v == 'no' ? false : null);
                          return SmCard(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                SmAmenityValue(
                                  label: 'Open',
                                  icon: Icons.door_front_door_outlined,
                                  value: tri(data?['open'] as String?),
                                ),
                                SmAmenityValue(
                                  label: 'Water',
                                  icon: Icons.water_drop_outlined,
                                  value: tri(data?['water'] as String?),
                                ),
                                SmAmenityValue(
                                  label: 'Usable',
                                  icon: Icons.check_circle_outline,
                                  value: tri(data?['usable'] as String?),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: SmTokens.s20),

                      // Ratings Stream + Sparkline
                      SmEyebrow('Recent Reviews'),
                      const SizedBox(height: SmTokens.s8),
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _ratingsStream,
                        builder: (context, snapshot) {
                          final ratings = snapshot.data ?? [];
                          if (ratings.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final List<double> stars = ratings
                              .take(15)
                              .map((r) => (r['stars'] as num).toDouble())
                              .toList()
                              .reversed
                              .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (stars.length >= 4) ...[
                                SizedBox(
                                  height: 40.0,
                                  width: double.infinity,
                                  child: CustomPaint(
                                    painter: SparklinePainter(
                                      stars,
                                      context.sm.brand,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: SmTokens.s12),
                              ],
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: ratings.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: SmTokens.s8),
                                itemBuilder: (context, index) {
                                  final rating = ratings[index];
                                  return SmCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // 2026-09-02: reviews are never
                                            // labelled with the author's Google
                                            // display name. (The rating doc id
                                            // is still account-derived — this
                                            // is not full anonymisation.)
                                            Text(
                                              'Community review',
                                              style: SmText.bodyStrong.copyWith(
                                                color: context.sm.ink,
                                              ),
                                            ),
                                            const Spacer(),
                                            Icon(
                                              Icons.star,
                                              color: context.sm.star,
                                              size: 14,
                                            ),
                                            Text(
                                              '${rating['stars']}',
                                              style: SmText.caption.copyWith(
                                                color: context.sm.ink2,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (rating['note'] != null &&
                                            rating['note']
                                                .toString()
                                                .isNotEmpty) ...[
                                          const SizedBox(height: SmTokens.s4),
                                          Text(
                                            rating['note'],
                                            style: SmText.body.copyWith(
                                              color: context.sm.ink2,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 40.0),
                      const SizedBox(
                        height: 40.0,
                      ), // extra padding for bottom dock
                    ],
                  ),
                ),
              ),

              // 10. Bottom dock
              Container(
                color: context.sm.bg,
                padding: const EdgeInsets.symmetric(
                  horizontal: SmTokens.s24,
                  vertical: SmTokens.s16,
                ),
                child: SmPrimaryButton(
                  label: 'Navigate',
                  icon: Icons.near_me_rounded,
                  onTap: () async {
                    // Resolve position: use widget.userPosition if available,
                    // otherwise fetch live with a 5s timeout, fallback to last-known.
                    Position? pos = widget.userPosition;
                    if (pos == null) {
                      try {
                        pos = await Geolocator.getCurrentPosition(
                          locationSettings: const LocationSettings(
                            accuracy: LocationAccuracy.medium,
                            timeLimit: Duration(seconds: 5),
                          ),
                        );
                      } catch (_) {
                        pos = await Geolocator.getLastKnownPosition();
                      }
                    }
                    if (pos == null) {
                      if (context.mounted) {
                        showAppSnackBar(
                          'Turn on location to get directions',
                          isError: true,
                        );
                      }
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }

                    final dist = Geolocator.distanceBetween(
                      pos.latitude,
                      pos.longitude,
                      widget.toilet.latitude,
                      widget.toilet.longitude,
                    );
                    final selectedMode = await showTravelModeSheet(
                      context,
                      distanceMeters: dist,
                    );
                    if (selectedMode == null) return;
                    if (!context.mounted) {
                      return;
                    }

                    CustomHapticsService.playCrispSuccess();
                    Navigator.of(context).pop();

                    final etaSeconds = selectedMode == TravelMode.driving
                        ? (dist / 11.1).round()
                        : selectedMode == TravelMode.bicycling
                        ? (dist / 4.1).round()
                        : (dist / 1.4).round();

                    await MapLauncher.launch(
                      destination: LatLng(
                        widget.toilet.latitude,
                        widget.toilet.longitude,
                      ),
                      toiletName: widget.toilet.name,
                      toiletId: widget.toilet.id,
                      etaSeconds: etaSeconds,
                      mode: selectedMode,
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // XP Badge
        if (_showBadge)
          AnimatedBuilder(
            animation: _badgeController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0.0, _badgeSlide.value),
                child: Opacity(
                  opacity: _badgeOpacity.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: context.sm.brand,
                      borderRadius: BorderRadius.circular(20.0),
                      boxShadow: [
                        BoxShadow(
                          color: context.sm.brand.withValues(alpha: 0.3),
                          blurRadius: 10.0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      "+20 XP",
                      style: SmText.bodyStrong.copyWith(
                        color: context.sm.onBrand,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final double maxVal = 5.0; // stars are 1 to 5
    final double minVal = 1.0;

    final double stepX = values.length > 1
        ? size.width / (values.length - 1)
        : 0;

    for (int i = 0; i < values.length; i++) {
      final double x = i * stepX;
      // invert Y axis so 5.0 is at the top
      final double normalizedY = (values[i] - minVal) / (maxVal - minVal);
      final double y = size.height - (normalizedY * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (int i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}
