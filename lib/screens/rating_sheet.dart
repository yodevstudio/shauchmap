import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/custom_haptics_service.dart';
import '../services/feedback_bus.dart' as fbus;
import '../main.dart' show showAppSnackBar;
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

class RatingSheet extends StatefulWidget {
  final Toilet toilet;
  final String? userId;
  final String? userName;
  final Map<String, dynamic>? existingRating;
  final VoidCallback? onSubmitted;

  const RatingSheet({
    super.key,
    required this.toilet,
    this.userId,
    this.userName,
    this.existingRating,
    this.onSubmitted,
  });

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _noteController = TextEditingController();

  int _ratingStars = 0;
  final List<String> _selectedTags = [];
  bool _isSubmitting = false;

  // Animation for +10 pts floating badge
  late AnimationController _badgeController;
  late Animation<double> _badgeOpacity;
  late Animation<double> _badgeSlide;
  bool _showBadge = false;

  @override
  void initState() {
    super.initState();
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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

    if (widget.existingRating != null) {
      _ratingStars = (widget.existingRating!['stars'] as num?)?.toInt() ?? 0;
      _noteController.text = widget.existingRating!['note'] as String? ?? '';
      final tags = widget.existingRating!['tags'];
      if (tags is List) {
        _selectedTags.addAll(tags.cast<String>());
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _badgeController.dispose();
    super.dispose();
  }

  Widget _buildTagChip(String tag, Color activeColor) {
    final bool isSelected = _selectedTags.contains(tag);
    final c = context.sm;
    return GestureDetector(
      onTap: () {
        CustomHapticsService.playToggleSnap();
        if (!mounted) return;
        setState(() {
          if (isSelected) {
            _selectedTags.remove(tag);
          } else {
            _selectedTags.add(tag);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: SmTokens.s12,
          vertical: SmTokens.s8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : c.surface,
          borderRadius: BorderRadius.circular(SmTokens.rPill),
          border: Border.all(
            color: isSelected ? activeColor : c.line,
            width: 1.5,
          ),
        ),
        child: Text(
          tag,
          style: SmText.caption.copyWith(
            color: isSelected ? Colors.white : c.ink2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<void> _submitRating() async {
    if (_ratingStars == 0) return;
    CustomHapticsService.playStepTransition(); // Emulate step transition double-click

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final resolvedUserId = widget.userId ?? user?.uid ?? 'anonymous';
      if (resolvedUserId == 'anonymous') {
        if (mounted) showAppSnackBar('Please sign in to rate.', isError: true);
        return;
      }
      final resolvedUserName =
          widget.userName ?? user?.displayName ?? 'Anonymous';

      final Map<String, dynamic> ratingData = {
        'user_id': resolvedUserId,
        'user_name': resolvedUserName,
        'stars': _ratingStars,
        'tags': _selectedTags,
        'note': _noteController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      };

      // 1. Submit rating (handles database transaction & point increment)
      await _firestoreService.addRating(widget.toilet.id, ratingData);
      fbus.Feedback.fire(fbus.FeedbackEvent.reward);

      // 2. Play the floating +10 pts animation from the submit button
      if (!mounted) return;
      setState(() {
        _showBadge = true;
      });
      _badgeController.forward();

      // 3. Wait 800ms for animation to finish, then dismiss sheet
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        Navigator.of(context).pop();
        showAppSnackBar('Thanks for rating! You earned 10 Scout Points.');
        widget.onSubmitted?.call();
      }
    } catch (e) {
      if (mounted) {
        CustomHapticsService.playHollowDecay();
        showAppSnackBar('Error submitting review: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final List<String> availableTags = _ratingStars <= 2
        ? ["Dirty", "Smelly", "No water", "Locked"]
        : ["Clean", "Safe", "Good water", "Would return"];

    final Color chipActiveColor = _ratingStars <= 2
        ? c.statusClosed
        : c.statusOpen;

    return Container(
      decoration: smSheetDecoration(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: SmTokens.s24,
            right: SmTokens.s24,
            top: SmTokens.s12,
            bottom: MediaQuery.of(context).viewInsets.bottom + SmTokens.s24,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: SmGrabHandle()),
                  const SizedBox(height: SmTokens.s12),
                  Text(
                    'Rate this toilet',
                    style: SmText.title.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: SmTokens.s4),
                  Text(
                    'Your rating helps the next person',
                    style: SmText.caption.copyWith(color: c.ink2),
                  ),
                  const SizedBox(height: SmTokens.s20),

                  // Star Rating row (60px each)
                  GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null || !mounted) return;
                      if (box.size.width <= 0) return;

                      final int index =
                          ((details.localPosition.dx / box.size.width) * 5)
                              .ceil()
                              .clamp(1, 5);

                      if (index != _ratingStars) {
                        CustomHapticsService.playStarScroll();
                        if (!mounted) return;
                        setState(() {
                          _ratingStars = index;
                          _selectedTags.clear();
                        });
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 1; i <= 5; i++)
                          SpringStar(
                            isFilled: i <= _ratingStars,
                            onTap: () {
                              fbus.Feedback.fire(fbus.FeedbackEvent.star);
                              if (!mounted) return;
                              setState(() {
                                _ratingStars = i;
                                _selectedTags.clear();
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24.0),

                  // Smart Tag logic transition
                  if (_ratingStars > 0) ...[
                    Text(
                      "Select tags",
                      style: SmText.caption.copyWith(color: c.ink2),
                    ),
                    const SizedBox(height: SmTokens.s12),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: availableTags
                          .map((tag) => _buildTagChip(tag, chipActiveColor))
                          .toList(),
                    ),
                    const SizedBox(height: SmTokens.s24),
                  ],

                  // Note Field (Optional)
                  TextField(
                    controller: _noteController,
                    style: SmText.body.copyWith(color: c.ink),
                    maxLines: 2,
                    maxLength: 300,
                    decoration: InputDecoration(
                      hintText: "Add a note (optional)",
                      hintStyle: SmText.body.copyWith(color: c.ink2),
                      filled: true,
                      fillColor: c.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SmTokens.rSmall),
                        borderSide: BorderSide(color: c.line, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SmTokens.rSmall),
                        borderSide: BorderSide(color: c.line, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SmTokens.rSmall),
                        borderSide: BorderSide(color: c.brand, width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: SmTokens.s24),

                  // Submit Button
                  SmPrimaryButton(
                    label: widget.existingRating != null
                        ? 'Update rating'
                        : 'Submit rating',
                    onTap: _isSubmitting || _ratingStars == 0
                        ? null
                        : _submitRating,
                  ),
                ],
              ),

              // Pulsing float point animation (+10 pts)
              if (_showBadge)
                AnimatedBuilder(
                  animation: _badgeController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0.0, _badgeSlide.value + 120.0),
                      child: Opacity(
                        opacity: _badgeOpacity.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14.0,
                            vertical: 8.0,
                          ),
                          decoration: BoxDecoration(
                            color: context.sm.brandSolid,
                            borderRadius: BorderRadius.circular(20.0),
                            boxShadow: [
                              BoxShadow(
                                color: context.sm.brandSolid.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 10.0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Text(
                            "+10 XP",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpringStar extends StatefulWidget {
  final bool isFilled;
  final VoidCallback onTap;

  const SpringStar({super.key, required this.isFilled, required this.onTap});

  @override
  State<SpringStar> createState() => _SpringStarState();
}

class _SpringStarState extends State<SpringStar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Spring overshoot animation: scales up to 1.3x and settles at 1.0x
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.3,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.3,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50.0,
      ),
    ]).animate(_controller);

    if (widget.isFilled) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant SpringStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFilled && !oldWidget.isFilled) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isFilled ? _scaleAnimation.value : 1.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Icon(
                Icons.star,
                color: widget.isFilled ? c.star : c.soft,
                size: 48.0,
              ),
            ),
          );
        },
      ),
    );
  }
}
