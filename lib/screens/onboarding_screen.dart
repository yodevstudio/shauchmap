import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onEmergency;

  const OnboardingScreen({
    super.key,
    required this.onDone,
    required this.onEmergency,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  static const int _total = 4;

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    widget.onDone();
  }

  Future<void> _emergency() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    widget.onEmergency();
  }

  void _next() {
    if (_page < _total - 1) {
      _controller.nextPage(duration: SmTokens.dEase, curve: Curves.easeInOut);
    } else {
      _complete();
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
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Emergency bypass — pinned on every page
            GestureDetector(
              onTap: _emergency,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: SmTokens.s12,
                  horizontal: SmTokens.s16,
                ),
                color: c.statusClosed.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    Icon(
                      Icons.emergency_outlined,
                      color: c.statusClosed,
                      size: 18,
                    ),
                    const SizedBox(width: SmTokens.s8),
                    Expanded(
                      child: Text(
                        'I need a toilet right now →',
                        style: SmText.bodyStrong.copyWith(
                          color: c.statusClosed,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _buildPage1(c),
                  _buildPage2(c),
                  _buildPage3(c),
                  _buildPage4(c),
                ],
              ),
            ),

            // Dot indicator + CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SmTokens.s24,
                SmTokens.s8,
                SmTokens.s24,
                SmTokens.s24,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < _total; i++)
                        AnimatedContainer(
                          duration: SmTokens.dEase,
                          width: _page == i ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _page == i ? c.brandSolid : c.line,
                            borderRadius: BorderRadius.circular(SmTokens.rPill),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: SmTokens.s16),
                  SmPrimaryButton(
                    label: _page < _total - 1
                        ? 'Continue'
                        : 'Allow location & start',
                    onTap: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Page 1: Promise
  Widget _buildPage1(SmColors c) => Padding(
    padding: const EdgeInsets.all(SmTokens.s32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(c.brandSolid, Icons.location_on, 48),
        const SizedBox(height: SmTokens.s24),
        Text(
          'Find a clean toilet,\nanywhere in India.',
          style: SmText.title.copyWith(color: c.ink),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SmTokens.s12),
        Text(
          '7,741 verified locations.\nOpen statuses. Community-checked.',
          style: SmText.body.copyWith(color: c.ink2),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  // Page 2: How GO works
  Widget _buildPage2(SmColors c) => Padding(
    padding: const EdgeInsets.all(SmTokens.s24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(c.brandSolid, Icons.touch_app_outlined, 44),
        const SizedBox(height: SmTokens.s24),
        Text(
          'One tap. Nearest open toilet.',
          style: SmText.title.copyWith(color: c.ink),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SmTokens.s24),
        _howRow(
          c,
          '1',
          Icons.my_location_rounded,
          'Tap GO',
          'Finds the closest open toilet instantly',
        ),
        const SizedBox(height: SmTokens.s16),
        _howRow(
          c,
          '2',
          Icons.near_me_rounded,
          'Tap Navigate',
          'Opens Maps with walking or driving directions',
        ),
      ],
    ),
  );

  // Page 3: Colour legend
  Widget _buildPage3(SmColors c) => Padding(
    padding: const EdgeInsets.all(SmTokens.s24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: SmTokens.s24),
        _circle(c.statusOpen, Icons.palette_outlined, 28),
        const SizedBox(height: SmTokens.s16),
        Text(
          'What the colours mean',
          style: SmText.title.copyWith(color: c.ink),
        ),
        const SizedBox(height: SmTokens.s20),
        _legendRow(
          c,
          c.statusOpen,
          Icons.check_circle_outline,
          'Open now',
          'Confirmed usable right now',
        ),
        _legendRow(
          c,
          c.statusClosed,
          Icons.schedule,
          'Closed',
          'Check back later',
        ),
        _legendRow(
          c,
          c.statusUnsure,
          Icons.help_outline,
          'Needs check',
          'Not verified recently',
        ),
        const SizedBox(height: SmTokens.s12),
        SmCard(
          child: Text(
            'Colour is never the only signal — we always show a word and icon too.',
            style: SmText.caption.copyWith(color: c.ink2),
          ),
        ),
      ],
    ),
  );

  // Page 4: Location permission + help pitch
  Widget _buildPage4(SmColors c) => Padding(
    padding: const EdgeInsets.all(SmTokens.s32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(c.brand, Icons.my_location_outlined, 44),
        const SizedBox(height: SmTokens.s24),
        Text(
          'Allow location access',
          style: SmText.title.copyWith(color: c.ink),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SmTokens.s12),
        Text(
          'ShauchMap needs your location to show the nearest toilets and guide you there. We never track you in the background.',
          style: SmText.body.copyWith(color: c.ink2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SmTokens.s24),
        SmCard(
          child: Row(
            children: [
              Icon(Icons.volunteer_activism_outlined, color: c.brand, size: 20),
              const SizedBox(width: SmTokens.s12),
              Expanded(
                child: Text(
                  'Add toilets you know — help thousands of people.',
                  style: SmText.caption.copyWith(color: c.ink2),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _circle(Color color, IconData icon, double size) => Container(
    width: 80,
    height: 80,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: size),
  );

  Widget _howRow(
    SmColors c,
    String step,
    IconData icon,
    String label,
    String sub,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: c.brandSolid, shape: BoxShape.circle),
        child: Center(
          child: Text(
            step,
            style: SmText.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      const SizedBox(width: SmTokens.s12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: SmText.bodyStrong.copyWith(color: c.ink)),
            Text(sub, style: SmText.caption.copyWith(color: c.ink2)),
          ],
        ),
      ),
    ],
  );

  Widget _legendRow(
    SmColors c,
    Color color,
    IconData icon,
    String label,
    String sub,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: SmTokens.s12),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: SmTokens.s12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: SmText.bodyStrong.copyWith(color: c.ink)),
            Text(sub, style: SmText.caption.copyWith(color: c.ink2)),
          ],
        ),
      ],
    ),
  );
}
