import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:collection/collection.dart';
import 'detail_sheet.dart';
import 'add_toilet_wizard.dart';
import '../services/firestore_service.dart';
import '../config/rollout_config.dart';
import '../services/custom_haptics_service.dart';
import '../main.dart' show showAppSnackBar;
import 'settings_screen.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';
import '../field_audit/field_audit_config.dart';
import '../field_audit/field_audit_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  final FirestoreService firestoreService;
  final bool isSignedIn;
  final String? userId;
  final VoidCallback onSignInRequest;
  final List<Toilet> allToilets;

  const ProfileScreen({
    super.key,
    required this.firestoreService,
    required this.isSignedIn,
    required this.userId,
    required this.onSignInRequest,
    required this.allToilets,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _deleteAccount(BuildContext context) async {
    // Step 1: Confirm intent
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.sm.surface,
        title: Text('Delete Account?', style: TextStyle(color: ctx.sm.ink)),
        content: Text(
          'This deletes your account, private profile, saved toilets, badges '
          'and public leaderboard profile.\n\n'
          'Some sanitation contributions you made — toilets added, ratings, '
          'condition checks, check-ins, reports and votes — may be retained '
          '(some public, some private) as community data. Your profile name '
          'and email are removed, but technical identifiers derived from your '
          'account may remain in retained records; they are not fully '
          'anonymised.\n\nThis cannot be undone.',
          style: TextStyle(color: ctx.sm.ink2, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: ctx.sm.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: ctx.sm.statusClosed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      // Step 2: Re-authenticate (Firebase requires this before deleteUser)
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // User cancelled re-auth
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await user.reauthenticateWithCredential(credential);

      // Step 3: Delete the private profile doc and the public leaderboard row
      // ATOMICALLY. A WriteBatch means one deletion cannot silently succeed
      // while the other is left behind. Failure here aborts before the Auth
      // deletion (Step 4) and surfaces to the user — it is NOT swallowed.
      final userId = user.uid;
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.delete(db.collection('users').doc(userId));
      batch.delete(db.collection('public_profiles').doc(userId));
      await batch.commit();

      // Best-effort: the private per-user cosmetic counters (a subcollection,
      // not auto-deleted with the parent). They are unreadable once the uid is
      // gone; a Cloud Function would scrub them properly. Failure here does not
      // block account deletion.
      try {
        final wardens = await db
            .collection('users')
            .doc(userId)
            .collection('toilet_wardens')
            .get();
        for (final d in wardens.docs) {
          await d.reference.delete();
        }
      } catch (_) {}

      // Step 4: Delete Firebase Auth user
      await user.delete();

      // Step 5: Sign out cleanly
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();

      if (context.mounted) {
        showAppSnackBar('Account deleted successfully.');
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          'Could not delete account: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  String _getLevelTitle(int xp) {
    if (xp < 100) return "Loo Scout";
    if (xp < 500) return "Hygiene Hero";
    if (xp < 1000) return "City Guardian";
    final int level = 1 + ((xp - 1000) ~/ 1000);
    return "Swachh Legend \u2022 Lv $level";
  }

  String _getNextLevelTitle(int xp) {
    if (xp < 100) return "Hygiene Hero";
    if (xp < 500) return "City Guardian";
    if (xp < 1000) return "Swachh Legend \u2022 Lv 1";
    final int level = 1 + ((xp - 1000) ~/ 1000);
    return "Swachh Legend \u2022 Lv ${level + 1}";
  }

  double _getLevelProgress(int xp) {
    if (xp < 100) return xp / 100.0;
    if (xp < 500) return (xp - 100) / 400.0; // 400 points to next level
    if (xp < 1000) return (xp - 500) / 500.0; // 500 points to next level
    return ((xp - 1000) % 1000) / 1000.0; // Infinite tiers
  }

  // Internal Field Audit Mode entry point. Compiled in every build but only
  // rendered when built with --dart-define=FIELD_AUDIT_MODE=true. Does not
  // require sign-in and never touches production Firestore.
  Widget _fieldAuditEntry(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const FieldAuditListScreen())),
      icon: const Icon(Icons.fact_check_outlined),
      label: const Text('Field Audit Mode (internal)'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    if (!widget.isSignedIn || widget.userId == null) {
      return SafeArea(
        bottom: false,
        child: Container(
          color: c.bg,
          padding: const EdgeInsets.all(SmTokens.s32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_circle_outlined, color: c.brand, size: 72.0),
              const SizedBox(height: SmTokens.s20),
              Text(
                "Join ShauchMap Scouts",
                style: SmText.title.copyWith(color: c.ink, height: 1.5),
              ),
              const SizedBox(height: SmTokens.s8),
              Text(
                "Sign in to track points, rate toilets, save locations, and guide the community.",
                textAlign: TextAlign.center,
                style: SmText.body.copyWith(color: c.ink2, height: 1.4),
              ),
              const SizedBox(height: SmTokens.s32),
              SmPrimaryButton(
                label: "Sign in with Google",
                icon: Icons.login,
                onTap: () {
                  CustomHapticsService.playStepTransition();
                  widget.onSignInRequest();
                },
              ),
              if (FieldAuditConfig.enabled) ...[
                const SizedBox(height: SmTokens.s16),
                _fieldAuditEntry(context),
              ],
            ],
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Container(
        color: c.bg,
        child: StreamBuilder<DocumentSnapshot>(
          stream: widget.firestoreService.getUserStream(widget.userId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: c.brandSolid),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  "Something went wrong. Please try again.",
                  style: SmText.body.copyWith(color: c.ink2),
                ),
              );
            }

            final userData =
                snapshot.data?.data() as Map<String, dynamic>? ?? {};
            final User? currentUser = FirebaseAuth.instance.currentUser;
            final String name =
                currentUser?.displayName ?? userData['name'] ?? 'Explorer';
            final String? photoUrl =
                currentUser?.photoURL ?? userData['photo_url'];
            final int scoutPoints =
                (userData['scout_points'] as num?)?.toInt() ?? 0;
            final List<dynamic> savedToilets = userData['saved_toilets'] ?? [];
            final List<dynamic> badges = userData['badges'] ?? [];

            void openAddWizard() {
              // the SAME rollout gate as main._startAddToiletFlow.
              // Both consumer entry points ("Add your first toilet" and the
              // dashed "+ Add a toilet" button) route through here.
              if (!RolloutConfig.addToiletEnabled) {
                showAppSnackBar(RolloutConfig.addToiletPausedMessage);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddToiletWizard(
                    firestoreService: widget.firestoreService,
                    userId: widget.userId!,
                    onRefreshToilets: () {},
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                SmTokens.s16,
                SmTokens.s16,
                SmTokens.s16,
                SmTokens.s32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1 — Profile header (on bg, no card)
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: c.brandSolid,
                        backgroundImage:
                            (photoUrl != null && photoUrl.isNotEmpty)
                            ? NetworkImage(photoUrl)
                            : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? Text(
                                name.trim().isNotEmpty
                                    ? name
                                          .trim()
                                          .split(' ')
                                          .map((w) => w.isNotEmpty ? w[0] : '')
                                          .take(2)
                                          .join()
                                          .toUpperCase()
                                    : 'E',
                                style: SmText.subhead.copyWith(
                                  color: c.onBrand,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: SmTokens.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SmText.title.copyWith(color: c.ink),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.settings_rounded,
                                    color: c.ink2,
                                    size: 22,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: SmTokens.s4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: SmTokens.s12,
                                vertical: SmTokens.s4,
                              ),
                              decoration: BoxDecoration(
                                color: c.brand.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  SmTokens.rPill,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 14,
                                    color: c.brand,
                                  ),
                                  const SizedBox(width: SmTokens.s4),
                                  Text(
                                    _getLevelTitle(scoutPoints),
                                    style: SmText.caption.copyWith(
                                      color: c.brand,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: SmTokens.s16),

                  // 2 — XP bar (no card — bare padding so track is visible against bg)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$scoutPoints XP',
                        style: SmText.bodyStrong.copyWith(color: c.ink),
                      ),
                      Text.rich(
                        TextSpan(
                          text: 'Next: ',
                          style: SmText.body.copyWith(color: c.ink2),
                          children: [
                            TextSpan(
                              text: _getNextLevelTitle(scoutPoints),
                              style: SmText.bodyStrong.copyWith(color: c.ink2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SmTokens.s8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SmTokens.rPill),
                    child: LinearProgressIndicator(
                      value: _getLevelProgress(scoutPoints),
                      minHeight: 10,
                      backgroundColor: c.soft,
                      valueColor: AlwaysStoppedAnimation<Color>(c.brandSolid),
                    ),
                  ),

                  const SizedBox(height: SmTokens.s16),

                  // 3 — Impact hero card (live count — fixes stale toilets_added_count)
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('toilets')
                        .where('added_by', isEqualTo: widget.userId)
                        .snapshots(),
                    builder: (context, addedSnap) {
                      final addedCount = addedSnap.data?.docs.length ?? 0;
                      return GestureDetector(
                        onTap: () {
                          CustomHapticsService.playTileSelect();
                          openAddWizard();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(SmTokens.s16),
                          decoration: BoxDecoration(
                            color: c.soft,
                            borderRadius: BorderRadius.circular(SmTokens.rCard),
                            border: Border.all(color: c.line, width: 1),
                            boxShadow: context.smSoft,
                          ),
                          child: Row(
                            children: [
                              if (addedCount == 0) ...[
                                Icon(
                                  Icons.add_location_alt_outlined,
                                  color: c.brand,
                                  size: 32,
                                ),
                                const SizedBox(width: SmTokens.s12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Add your first toilet',
                                        style: SmText.title.copyWith(
                                          color: c.brand,
                                        ),
                                      ),
                                      Text(
                                        'help your city',
                                        style: SmText.body.copyWith(
                                          color: c.ink2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  '$addedCount',
                                  style: SmText.hero.copyWith(color: c.brand),
                                ),
                                const SizedBox(width: SmTokens.s16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'toilets you put on the map',
                                        style: SmText.subhead.copyWith(
                                          color: c.ink,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        'keep your city moving',
                                        style: SmText.body.copyWith(
                                          color: c.ink2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: SmTokens.s12),

                  // 4 — Dashed "+ Add a toilet" button
                  GestureDetector(
                    onTap: openAddWizard,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(SmTokens.rCard),
                        border: Border.all(
                          color: c.brand.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, color: c.brand, size: 20),
                          const SizedBox(width: SmTokens.s8),
                          Text(
                            'Add a toilet',
                            style: SmText.bodyStrong.copyWith(color: c.brand),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: SmTokens.s24),

                  // 5 — Top scouts. Reads the world-readable public_profiles
                  // collection (name / photo_url / scout_points only) — NOT the
                  // private /users docs. scout_points is client-authored, so
                  // this is a self-reported cosmetic ranking, not a trusted one.
                  const SmEyebrow("TOP SCOUTS"),
                  const SizedBox(height: SmTokens.s12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('public_profiles')
                        .orderBy('scout_points', descending: true)
                        .limit(5)
                        .snapshots(),
                    builder: (context, leaderSnap) {
                      if (leaderSnap.connectionState ==
                          ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(color: c.brandSolid),
                        );
                      }
                      final docs = leaderSnap.data?.docs ?? [];
                      final bool userInTop = docs.any(
                        (d) => d.id == widget.userId,
                      );

                      Widget rankBadge(int rank, bool isCurrentUser) {
                        final Color bg = isCurrentUser
                            ? c.brandSolid
                            : rank == 1
                            ? const Color(0xFFFFD700).withValues(alpha: 0.25)
                            : rank == 2
                            ? const Color(0xFFC0C0C0).withValues(alpha: 0.3)
                            : rank == 3
                            ? const Color(0xFFCD7F32).withValues(alpha: 0.25)
                            : c.soft;
                        final Color fg = isCurrentUser
                            ? c.onBrand
                            : rank <= 3
                            ? c.ink
                            : c.ink2;
                        return Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(
                              SmTokens.rSmall,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$rank',
                              style: SmText.bodyStrong.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          ...docs.asMap().entries.map((entry) {
                            final rank = entry.key + 1;
                            final doc = entry.value;
                            final data =
                                doc.data() as Map<String, dynamic>? ?? {};
                            final bool isMe = doc.id == widget.userId;
                            final String rowName = isMe
                                ? 'You'
                                : (data['name'] ?? 'Scout');
                            final int pts =
                                (data['scout_points'] as num?)?.toInt() ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: SmTokens.s8,
                              ),
                              child: SmCard(
                                child: Row(
                                  children: [
                                    rankBadge(rank, isMe),
                                    const SizedBox(width: SmTokens.s12),
                                    Expanded(
                                      child: Text(
                                        rowName,
                                        style: SmText.bodyStrong.copyWith(
                                          color: c.ink,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      pts >= 1000
                                          ? '${(pts / 1000).toStringAsFixed(pts % 1000 == 0 ? 0 : 1)}k'
                                          : '$pts',
                                      style: SmText.bodyStrong.copyWith(
                                        color: c.brand,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (!userInTop && scoutPoints > 0)
                            SmCard(
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: c.brandSolid,
                                      borderRadius: BorderRadius.circular(
                                        SmTokens.rSmall,
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.person,
                                        size: 18,
                                        color: c.onBrand,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: SmTokens.s12),
                                  const Expanded(
                                    child: Text(
                                      'You',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$scoutPoints',
                                    style: SmText.bodyStrong.copyWith(
                                      color: c.brand,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: SmTokens.s24),

                  // Badges Section
                  if (badges.isNotEmpty) ...[
                    const SmEyebrow('EARNED BADGES'),
                    const SizedBox(height: SmTokens.s8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      child: Row(
                        children:
                            [
                              {'id': 'first_scout', 'name': 'First Scout'},
                              {'id': 'mapper', 'name': 'Mapper'},
                              {'id': 'cartographer', 'name': 'Cartographer'},
                              {'id': 'reviewer', 'name': 'Reviewer'},
                              {'id': 'guardian', 'name': 'Guardian'},
                              {'id': 'legend', 'name': 'Legend'},
                            ].where((b) => badges.contains(b['id'])).map((
                              badgeData,
                            ) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  right: SmTokens.s12,
                                ),
                                child: SmCard(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shield,
                                        color: c.star,
                                        size: 20.0,
                                      ),
                                      const SizedBox(width: SmTokens.s8),
                                      Text(
                                        badgeData['name']!,
                                        style: SmText.bodyStrong.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: SmTokens.s32),

                  // Toilets I Added Section
                  const SmEyebrow('TOILETS I ADDED'),
                  const SizedBox(height: SmTokens.s12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('toilets')
                        .where('added_by', isEqualTo: widget.userId)
                        .orderBy('created_at', descending: true)
                        .limit(10)
                        .snapshots(),
                    builder: (context, fsSnapshot) {
                      if (fsSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(color: c.brandSolid),
                        );
                      }
                      if (fsSnapshot.hasError) {
                        return SmCard(
                          child: Row(
                            children: [
                              Icon(Icons.cloud_off, color: c.ink3, size: 20.0),
                              const SizedBox(width: SmTokens.s12),
                              Expanded(
                                child: Text(
                                  'Could not load your toilets. Check your connection.',
                                  style: SmText.body.copyWith(color: c.ink2),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!fsSnapshot.hasData) return const SizedBox.shrink();

                      final List<DocumentSnapshot> displayedDocs =
                          fsSnapshot.data!.docs;

                      if (displayedDocs.isEmpty) {
                        return Text(
                          "You haven't added any toilets yet. Be the first in your area!",
                          style: SmText.body.copyWith(color: c.ink2),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayedDocs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: SmTokens.s12),
                        itemBuilder: (context, index) {
                          final doc = displayedDocs[index];
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final String name = data['name'] ?? '';
                          // Classification via the identity-truth layer, never
                          // the raw `category` string (base OSM = hard-coded
                          // 'govt'). Unknown => "Mapped toilet".
                          final String catLabel = ToiletPresentation.fromToilet(
                            toiletFromFirestore(doc),
                          ).contextLabel;

                          return SmCard(
                            onTap: () {
                              CustomHapticsService.playTileSelect();
                              final String toiletId = doc.id;
                              final Toilet? found = widget.allToilets
                                  .firstWhereOrNull((t) => t.id == toiletId);
                              if (found != null && context.mounted) {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (ctx) => FractionallySizedBox(
                                    heightFactor: 0.9,
                                    child: DetailSheet(
                                      toilet: found,
                                      isSignedIn: widget.isSignedIn,
                                      userId: widget.userId,
                                      userName: FirebaseAuth
                                          .instance
                                          .currentUser
                                          ?.displayName,
                                      onSignInRequest: widget.onSignInRequest,
                                      onRefreshToilets: () {},
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: SmText.title.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                      const SizedBox(height: SmTokens.s4),
                                      Text(
                                        catLabel,
                                        style: SmText.caption.copyWith(
                                          color: c.ink2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: SmTokens.s8),
                                Icon(
                                  Icons.chevron_right,
                                  color: c.ink3,
                                  size: 20.0,
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: SmTokens.s32),

                  // Saved toilets list header
                  const SmEyebrow('SAVED TOILET BOOKMARKS'),
                  const SizedBox(height: SmTokens.s12),

                  savedToilets.isEmpty
                      ? Text(
                          "No saved loos yet. Keep track of the best spots around town.",
                          style: SmText.body.copyWith(color: c.ink2),
                        )
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('toilets')
                              .where(
                                FieldPath.documentId,
                                whereIn: savedToilets
                                    .cast<String>()
                                    .take(30)
                                    .toList(),
                              )
                              .snapshots(),
                          builder: (context, mapSnapshot) {
                            if (mapSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                child: CircularProgressIndicator(
                                  color: c.brandSolid,
                                ),
                              );
                            }
                            if (mapSnapshot.hasError) {
                              return Text(
                                "Something went wrong. Please try again.",
                                style: SmText.body.copyWith(color: c.ink2),
                              );
                            }
                            if (!mapSnapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final savedDocs = mapSnapshot.data!.docs.toList();

                            if (savedDocs.isEmpty) {
                              return Text(
                                "No saved loos yet. Keep track of the best spots around town.",
                                style: SmText.body.copyWith(color: c.ink2),
                              );
                            }

                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: savedDocs.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: SmTokens.s12),
                              itemBuilder: (context, index) {
                                final doc = savedDocs[index];
                                final String name = doc['name'] ?? '';
                                final String address = doc['address'] ?? '';

                                return SmCard(
                                  onTap: () {
                                    CustomHapticsService.playTileSelect();
                                    final String toiletId = doc.id;
                                    final Toilet? found = widget.allToilets
                                        .firstWhereOrNull(
                                          (t) => t.id == toiletId,
                                        );
                                    if (found != null && context.mounted) {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (ctx) => FractionallySizedBox(
                                          heightFactor: 0.9,
                                          child: DetailSheet(
                                            toilet: found,
                                            isSignedIn: widget.isSignedIn,
                                            userId: widget.userId,
                                            userName: FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.displayName,
                                            onSignInRequest:
                                                widget.onSignInRequest,
                                            onRefreshToilets: () {},
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.replaceAll('\n', ' '),
                                        style: SmText.title.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                      const SizedBox(height: SmTokens.s4),
                                      Text(
                                        address,
                                        style: SmText.caption.copyWith(
                                          color: c.ink2,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                  const SizedBox(height: SmTokens.s32),
                  TextButton(
                    onPressed: () async {
                      CustomHapticsService.playToggleSnap();
                      await FirebaseAuth.instance.signOut();
                    },
                    child: Text(
                      'Sign Out',
                      style: SmText.subhead.copyWith(color: c.ink3),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _deleteAccount(context),
                    child: Text(
                      'Delete Account',
                      style: SmText.caption.copyWith(color: c.statusClosed),
                    ),
                  ),
                  if (FieldAuditConfig.enabled) ...[
                    const SizedBox(height: 12.0),
                    _fieldAuditEntry(context),
                  ],
                  const SizedBox(height: 24.0),
                  _DevEasterEgg(),
                  const SizedBox(height: 16.0),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Triple-tap the version badge to see who built this.
// If you're reading the source: 👋 welcome to the code.
class _DevEasterEgg extends StatefulWidget {
  const _DevEasterEgg();
  @override
  State<_DevEasterEgg> createState() => _DevEasterEggState();
}

class _DevEasterEggState extends State<_DevEasterEgg> {
  int _taps = 0;
  bool _revealed = false;

  void _onTap() {
    setState(() {
      _taps++;
      if (_taps >= 3) {
        _revealed = true;
        _taps = 0;
      }
    });
    if (_revealed) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _revealed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _revealed
            ? Padding(
                key: const ValueKey('egg'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      'crafted by yodevstudio ✦',
                      style: SmText.caption.copyWith(
                        color: c.brand,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'every toilet matters.',
                      style: SmText.caption.copyWith(
                        color: c.ink3,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              )
            : Padding(
                key: const ValueKey('ver'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'shauchmap v1.0',
                  style: SmText.caption.copyWith(color: c.ink3),
                ),
              ),
      ),
    );
  }
}
