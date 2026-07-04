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
  }

  @override
  void dispose() {
    _badgeController.dispose();
    super.dispose();
  }

  Widget _voteBtn({required bool up}) {
    final c = context.sm;
    final active = _userVote == up;
    final accent = up ? c.statusOpen : c.statusClosed;
    final count = up ? widget.toilet.upvoteCount : widget.toilet.downvoteCount;
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
              '$count',
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

  String _getOpenStatusText(Toilet toilet) {
    if (!toilet.isOpen) {
      return "Closed";
    }
    final hour = DateTime.now().hour;
    if (hour >= 20) {
      return "Open · closes at 10 PM";
    }
    return "Open";
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
    Share.share(
      "📍 ${widget.toilet.name.replaceAll('\n', ' ')}\n⭐ ${widget.toilet.starRating.toStringAsFixed(1)} Stars\n🚶 ${widget.toilet.address}\n\nView and navigate on ShauchMap.",
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
    );
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final openStatus = widget.toilet.isOpen ? SmStatus.open : SmStatus.closed;
    final openText = _getOpenStatusText(widget.toilet);

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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.category_outlined,
                                size: 14,
                                color: context.sm.ink3,
                              ),
                              const SizedBox(width: SmTokens.s4),
                              Text(
                                widget.toilet.category.toUpperCase(),
                                style: SmText.caption.copyWith(
                                  color: context.sm.ink2,
                                ),
                              ),
                            ],
                          ),
                          SmFilterChip(
                            label: widget.toilet.isFree ? "Free" : "Paid",
                            selected: false,
                            onTap: () {},
                          ),
                          SmStatusLabel(openStatus, text: openText),
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

                      // 6. Trust card
                      SmCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: context.sm.statusOpen,
                                  size: 18,
                                ),
                                const SizedBox(width: SmTokens.s8),
                                Text(
                                  'Usable right now',
                                  style: SmText.bodyStrong.copyWith(
                                    color: context.sm.statusOpen,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: SmTokens.s4),
                            Text(
                              '${widget.toilet.communityScore > 0 ? "${(widget.toilet.communityScore * 100).round()}% people confirmed" : "Not yet verified"} · checked recently',
                              style: SmText.caption.copyWith(
                                color: context.sm.ink2,
                              ),
                            ),
                          ],
                        ),
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
                                                "Thanks for reporting. We'll review this shortly.",
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

                      // 8. Amenities section
                      SmEyebrow('What\'s inside'),
                      const SizedBox(height: SmTokens.s8),
                      SmCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            SmAmenityValue(
                              label: 'Water',
                              icon: Icons.water_drop_outlined,
                              value: widget.toilet.hasWater,
                            ),
                            Divider(color: context.sm.surface, height: 1),
                            SmAmenityValue(
                              label: 'Soap',
                              icon: Icons.soap_outlined,
                              value: widget.toilet.hasSoap,
                            ),
                            Divider(color: context.sm.surface, height: 1),
                            SmAmenityValue(
                              label: 'Lock works',
                              icon: Icons.lock_outlined,
                              value: widget.toilet.hasLock,
                            ),
                            Divider(color: context.sm.surface, height: 1),
                            SmAmenityValue(
                              label: 'Wheelchair',
                              icon: Icons.accessible_outlined,
                              value: widget.toilet.isWheelchair,
                            ),
                            Divider(color: context.sm.surface, height: 1),
                            SmAmenityValue(
                              label: 'Baby changing',
                              icon: Icons.baby_changing_station,
                              value: widget.toilet.hasBabyChange,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: SmTokens.s20),

                      // 9. Women-safe
                      if (widget.toilet.isWomenSafe) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SmTokens.s12,
                              vertical: SmTokens.s4,
                            ),
                            decoration: BoxDecoration(
                              color: context.sm.womenSafe.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(
                                color: context.sm.womenSafe,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              "Women Safe — verified recently",
                              style: SmText.caption.copyWith(
                                color: context.sm.womenSafe,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: SmTokens.s20),
                      ],

                      // Live Status
                      SmEyebrow('Live Status'),
                      const SizedBox(height: SmTokens.s8),
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _firestoreService.getRecentQuickChecks(
                          widget.toilet.id,
                        ),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox.shrink();
                          }
                          final checks = snapshot.data ?? [];
                          bool hasRecent = false;
                          if (checks.isNotEmpty) {
                            final ts = checks.first['timestamp'];
                            if (ts != null) {
                              hasRecent =
                                  DateTime.now()
                                      .difference((ts as Timestamp).toDate())
                                      .inHours <
                                  24;
                            }
                          }
                          if (!hasRecent) {
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
                                      "Status unknown today.",
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
                          final check = checks.first;
                          final bool water =
                              check['has_water'] as bool? ?? false;
                          final bool lock =
                              check['door_locks'] as bool? ?? false;
                          final bool safe =
                              check['safe_approach'] as bool? ?? false;
                          return SmCard(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                SmAmenityValue(
                                  label: 'Water',
                                  icon: Icons.water_drop_outlined,
                                  value: water,
                                ),
                                SmAmenityValue(
                                  label: 'Lock',
                                  icon: Icons.lock_outlined,
                                  value: lock,
                                ),
                                SmAmenityValue(
                                  label: 'Safe',
                                  icon: Icons.health_and_safety_outlined,
                                  value: safe,
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
                                            Text(
                                              rating['user_name'] ??
                                                  'Anonymous',
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
