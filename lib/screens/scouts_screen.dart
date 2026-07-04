import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

class ScoutsScreen extends StatelessWidget {
  final String? userId;

  const ScoutsScreen({super.key, required this.userId});

  String _getRankTitle(int xp) {
    if (xp < 100) return 'Loo Scout';
    if (xp < 500) return 'Hygiene Hero';
    if (xp < 1000) return 'City Guardian';
    final int level = 1 + ((xp - 1000) ~/ 1000);
    return 'Swachh Legend \u2022 Lv $level';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return Container(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SmTokens.s24,
              vertical: SmTokens.s16,
            ),
            child: SmEyebrow('Top scouts'),
          ),
          Divider(color: c.soft, height: 1.0),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('scout_points', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: c.brandSolid),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Could not load leaderboard",
                      style: SmText.body.copyWith(color: c.ink2),
                    ),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(SmTokens.s32),
                      child: Text(
                        "No scouts yet. Be the first to add a toilet.",
                        textAlign: TextAlign.center,
                        style: SmText.body.copyWith(color: c.ink2),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final String name = data['name'] as String? ?? 'Explorer';
                    final String? photoUrl = data['photo_url'] as String?;
                    final int xp = (data['scout_points'] as num?)?.toInt() ?? 0;
                    final int rank = index + 1;
                    final bool isCurrentUser =
                        userId != null && doc.id == userId;

                    Color rankColor = const Color(0xFF8E8E93);
                    if (rank == 1) {
                      rankColor = const Color(0xFFFFD700);
                    } else if (rank == 2) {
                      rankColor = const Color(0xFFC0C0C0);
                    } else if (rank == 3) {
                      rankColor = const Color(0xFFCD7F32);
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SmTokens.s16,
                        vertical: SmTokens.s4,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(SmTokens.s16),
                        decoration: BoxDecoration(
                          color: isCurrentUser ? c.soft : c.surface,
                          borderRadius: BorderRadius.circular(SmTokens.rCard),
                          boxShadow: SmShadow.softLight,
                        ),
                        child: Row(
                          children: [
                            SmCard(
                              heavy: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: SmTokens.s12,
                                vertical: SmTokens.s8,
                              ),
                              child: Text(
                                '#$rank',
                                style: SmText.title.copyWith(color: rankColor),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: SmTokens.s12),
                            CircleAvatar(
                              radius: SmTokens.s20,
                              backgroundColor: c.brandSolid,
                              backgroundImage:
                                  (photoUrl != null && photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : 'E',
                                      style: SmText.title.copyWith(
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: SmTokens.s12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SmText.subhead.copyWith(
                                      color: isCurrentUser ? c.brand : c.ink,
                                    ),
                                  ),
                                  const SizedBox(height: SmTokens.s4),
                                  Text(
                                    _getRankTitle(xp),
                                    style: SmText.caption.copyWith(
                                      color: c.ink2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$xp XP',
                              style: SmText.subhead.copyWith(color: rankColor),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
