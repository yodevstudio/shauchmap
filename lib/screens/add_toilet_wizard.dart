import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/firestore_service.dart';
import '../services/custom_haptics_service.dart';
import '../map_style.dart';
import '../services/feedback_bus.dart' as fbus;
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';
import '../main.dart' show showAppSnackBar;

class AddToiletWizard extends StatefulWidget {
  final FirestoreService firestoreService;
  final String userId;
  final VoidCallback onRefreshToilets;
  final VoidCallback onClose;

  const AddToiletWizard({
    super.key,
    required this.firestoreService,
    required this.userId,
    required this.onRefreshToilets,
    required this.onClose,
  });

  @override
  State<AddToiletWizard> createState() => _AddToiletWizardState();
}

class _AddToiletWizardState extends State<AddToiletWizard>
    with SingleTickerProviderStateMixin {
  int _addWizardStep =
      1; // 1: Camera, 2: Map Location, 3: Category, 4: Details, 5: Success

  // Truth V2: the wizard establishes that a mapped facility EXISTS. It writes
  // NO fabricated legacy defaults — no `is_open`, and no hidden `category` /
  // `gender_type`. Identity (context + gender), fee and amenities are all
  // explicit three-state with UNKNOWN as the real, submittable default, and
  // are serialised in a native `truth_v2` block.
  FacilityContext _context = FacilityContext.unknown;
  GenderAccess _gender = GenderAccess.unknown;
  FeeState _fee = FeeState.unknown;
  EvidenceState _water = EvidenceState.unknown;
  EvidenceState _soap = EvidenceState.unknown;
  EvidenceState _lock = EvidenceState.unknown;
  EvidenceState _western = EvidenceState.unknown;
  EvidenceState _wheelchair = EvidenceState.unknown;
  EvidenceState _babyChange = EvidenceState.unknown;
  EvidenceState _sanitaryDisposal = EvidenceState.unknown;
  final TextEditingController _addNameController = TextEditingController();
  final TextEditingController _addLandmarkController = TextEditingController();
  LatLng _selectedAddCoords = const LatLng(
    26.29,
    73.03,
  ); // Default Jodhpur fallback
  LatLng? _userLocation;
  int _totalToiletCount = 0;

  bool _isResolvingAddress = false;

  // Animation for +50 XP
  late AnimationController _badgeController;
  late Animation<double> _badgeOpacity;
  late Animation<double> _badgeSlide;
  bool _showBadge = false;

  @override
  void initState() {
    super.initState();
    _fetchUserLocation();

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
  }

  Future<void> _fetchUserLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _userLocation = LatLng(pos.latitude, pos.longitude);
          _selectedAddCoords = _userLocation!;
        });
        _reverseGeocode(_selectedAddCoords);
      }
    } catch (_) {
      // Keep default Jodhpur coords as fallback only
      _reverseGeocode(_selectedAddCoords);
    }
  }

  Future<void> _reverseGeocode(LatLng target) async {
    if (!mounted) {
      return;
    }
    setState(() => _isResolvingAddress = true);
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        target.latitude,
        target.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        setState(() {
          _isResolvingAddress = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isResolvingAddress = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResolvingAddress = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _badgeController.dispose();
    _addNameController.dispose();
    _addLandmarkController.dispose();
    super.dispose();
  }

  // Called by the top-right ✕ button to fully exit the wizard.
  // Shows a discard-confirm dialog if the user has entered any data,
  // then calls widget.onClose() which returns to the Map tab.
  // The phone-Back / PopScope step-back path is SEPARATE and NOT routed here.
  Future<void> _handleCloseRequest() async {
    final bool hasData =
        _addNameController.text.isNotEmpty ||
        _addLandmarkController.text.isNotEmpty;
    if (hasData) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: context.sm.surface,
          title: Text(
            "Discard new toilet?",
            style: TextStyle(color: context.sm.ink),
          ),
          content: Text(
            "Your entered details will be lost.",
            style: TextStyle(color: context.sm.ink2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text("Cancel", style: TextStyle(color: context.sm.ink2)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                "Discard",
                style: TextStyle(color: context.sm.statusClosed),
              ),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        widget.onClose();
      }
    } else {
      widget.onClose();
    }
  }

  // Compact three-state row: a label and a segmented Unknown / Yes / No picker.
  // Unknown is a first-class choice, not an "unset" — the submitter can leave it
  // or pick it deliberately.
  Widget _triRow(
    String title,
    EvidenceState value,
    ValueChanged<EvidenceState> onChange,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SmTokens.s8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: SmText.body.copyWith(color: context.sm.ink),
            ),
          ),
          const SizedBox(width: SmTokens.s8),
          _Segmented<EvidenceState>(
            value: value,
            options: const [
              (EvidenceState.unknown, 'Unknown'),
              (EvidenceState.present, 'Yes'),
              (EvidenceState.absent, 'No'),
            ],
            onChanged: (v) {
              CustomHapticsService.playAsymmetricChoice(
                v == EvidenceState.present,
              );
              onChange(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAddWizardContent() {
    if (_addWizardStep == 5) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: SmTokens.s24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 80.0,
                height: 80.0,
                decoration: BoxDecoration(
                  color: context.sm.brandSolid,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 48.0),
              ),
            ),
            const SizedBox(height: SmTokens.s24),
            Text(
              "Thank you! You helped everyone nearby.",
              textAlign: TextAlign.center,
              style: SmText.title.copyWith(color: context.sm.ink),
            ),
            const SizedBox(height: SmTokens.s8),
            Text(
              "+50 scout points added to your profile.",
              textAlign: TextAlign.center,
              style: SmText.body.copyWith(color: context.sm.ink2),
            ),
            const SizedBox(height: SmTokens.s12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield, color: context.sm.star, size: 20.0),
                const SizedBox(width: SmTokens.s8),
                Text(
                  "First Scout Badge Unlocked!",
                  style: SmText.bodyStrong.copyWith(color: context.sm.star),
                ),
              ],
            ),
            const SizedBox(height: SmTokens.s16),
            Text(
              "ShauchMap now has $_totalToiletCount toilets.",
              textAlign: TextAlign.center,
              style: SmText.bodyStrong.copyWith(color: context.sm.brand),
            ),
            const Spacer(),
            SmPrimaryButton(
              label: "Close",
              icon: Icons.close,
              onTap: () {
                widget.onRefreshToilets();
                widget.onClose();
              },
            ),
            const SizedBox(height: SmTokens.s32),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(SmTokens.s16),
            children: [
              SmCard(
                heavy: true,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(SmTokens.rCard),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target:
                                    _userLocation ?? const LatLng(26.29, 73.03),
                                zoom: 18.5,
                              ),
                              style: darkMapStyle,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              onMapCreated: (controller) {},
                              onCameraMove: (position) {
                                _selectedAddCoords = position.target;
                                if (!_isResolvingAddress)
                                  setState(() => _isResolvingAddress = true);
                              },
                              onCameraIdle: () {
                                _reverseGeocode(_selectedAddCoords);
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: Icon(
                                Icons.location_on,
                                color: context.sm.brandSolid,
                                size: 48.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(SmTokens.s12),
                      decoration: BoxDecoration(
                        color: context.sm.surface,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(SmTokens.rCard),
                        ),
                        border: Border(top: BorderSide(color: context.sm.line)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.my_location,
                            color: context.sm.brand,
                            size: 16,
                          ),
                          const SizedBox(width: SmTokens.s8),
                          Text(
                            'Your location · drag to adjust',
                            style: SmText.caption.copyWith(
                              color: context.sm.ink2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SmTokens.s24),

              SmCard(
                padding: const EdgeInsets.all(SmTokens.s16),
                child: Row(
                  children: [
                    Icon(Icons.camera_alt_outlined, color: context.sm.ink3),
                    const SizedBox(width: SmTokens.s8),
                    Text(
                      'Add photos',
                      style: SmText.body.copyWith(color: context.sm.ink3),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.sm.statusUnsure.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(SmTokens.rPill),
                      ),
                      child: Text(
                        'v1.1',
                        style: SmText.caption.copyWith(
                          color: context.sm.statusUnsure,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SmTokens.s24),

              SmEyebrow('Loo Name'),
              const SizedBox(height: SmTokens.s8),
              TextField(
                controller: _addNameController,
                style: SmText.body.copyWith(color: context.sm.ink),
                decoration: InputDecoration(
                  hintText: 'e.g. Clock Tower Public Toilet',
                  hintStyle: SmText.body.copyWith(color: context.sm.ink3),
                  filled: true,
                  fillColor: context.sm.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SmTokens.rSmall),
                    borderSide: BorderSide(color: context.sm.line),
                  ),
                ),
              ),
              const SizedBox(height: SmTokens.s24),

              SmEyebrow('Toilet setting'),
              const SizedBox(height: SmTokens.s4),
              Text(
                "What kind of place is this? Leave as Unknown if unsure.",
                style: SmText.caption.copyWith(color: context.sm.ink3),
              ),
              const SizedBox(height: SmTokens.s8),
              Wrap(
                spacing: SmTokens.s8,
                runSpacing: SmTokens.s8,
                children: [
                  for (final (ctx, label, icon) in const [
                    (FacilityContext.unknown, 'Unknown', Icons.help_outline),
                    (
                      FacilityContext.publicToilet,
                      'Public toilet',
                      Icons.wc_outlined,
                    ),
                    (
                      FacilityContext.petrolStation,
                      'Petrol pump',
                      Icons.local_gas_station_outlined,
                    ),
                    (
                      FacilityContext.commercial,
                      'Mall / shop',
                      Icons.shopping_bag_outlined,
                    ),
                    (FacilityContext.station, 'Station', Icons.train_outlined),
                    (FacilityContext.other, 'Other', Icons.more_horiz),
                  ])
                    SmFilterChip(
                      label: label,
                      icon: icon,
                      selected: _context == ctx,
                      onTap: () => setState(() => _context = ctx),
                    ),
                ],
              ),
              const SizedBox(height: SmTokens.s24),

              SmEyebrow('Who is it for?'),
              const SizedBox(height: SmTokens.s8),
              Wrap(
                spacing: SmTokens.s8,
                runSpacing: SmTokens.s8,
                children: [
                  for (final (g, label) in const [
                    (GenderAccess.unknown, 'Unknown'),
                    (GenderAccess.unisex, 'Unisex'),
                    (GenderAccess.men, 'Men'),
                    (GenderAccess.women, 'Women'),
                  ])
                    SmFilterChip(
                      label: label,
                      selected: _gender == g,
                      onTap: () => setState(() => _gender = g),
                    ),
                ],
              ),
              const SizedBox(height: SmTokens.s24),

              SmEyebrow('Cost'),
              const SizedBox(height: SmTokens.s8),
              _Segmented<FeeState>(
                value: _fee,
                options: const [
                  (FeeState.unknown, 'Unknown'),
                  (FeeState.free, 'Free'),
                  (FeeState.paid, 'Pay (₹)'),
                ],
                onChanged: (v) {
                  CustomHapticsService.playAsymmetricChoice(v == FeeState.free);
                  setState(() => _fee = v);
                },
              ),
              const SizedBox(height: SmTokens.s24),

              SmEyebrow("What's there?"),
              const SizedBox(height: SmTokens.s4),
              Text(
                "Describe the FACILITY, not its state right now. Leave anything "
                "you didn't see as Unknown.",
                style: SmText.caption.copyWith(color: context.sm.ink3),
              ),
              const SizedBox(height: SmTokens.s8),
              SmCard(
                padding: const EdgeInsets.all(SmTokens.s16),
                child: Column(
                  children: [
                    _triRow(
                      "Water facility",
                      _water,
                      (v) => setState(() => _water = v),
                    ),
                    _triRow("Soap", _soap, (v) => setState(() => _soap = v)),
                    _triRow(
                      "Door / lock",
                      _lock,
                      (v) => setState(() => _lock = v),
                    ),
                    _triRow(
                      "Western seat",
                      _western,
                      (v) => setState(() => _western = v),
                    ),
                    _triRow(
                      "Wheelchair access",
                      _wheelchair,
                      (v) => setState(() => _wheelchair = v),
                    ),
                    _triRow(
                      "Baby changing",
                      _babyChange,
                      (v) => setState(() => _babyChange = v),
                    ),
                    _triRow(
                      "Sanitary disposal",
                      _sanitaryDisposal,
                      (v) => setState(() => _sanitaryDisposal = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SmTokens.s24),

              SmEyebrow('How to find it? (optional)'),
              const SizedBox(height: SmTokens.s8),
              TextField(
                controller: _addLandmarkController,
                style: SmText.body.copyWith(color: context.sm.ink),
                decoration: InputDecoration(
                  hintText: 'e.g. Behind SBI ATM, next to petrol pump',
                  hintStyle: SmText.body.copyWith(color: context.sm.ink3),
                  filled: true,
                  fillColor: context.sm.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SmTokens.rSmall),
                    borderSide: BorderSide(color: context.sm.line),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(SmTokens.s16),
          decoration: BoxDecoration(
            color: context.sm.bg,
            border: Border(top: BorderSide(color: context.sm.line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmPrimaryButton(
                label: 'Add toilet · help your city',
                icon: Icons.add_location_alt_outlined,
                onTap: () async {
                  final String name = _addNameController.text.trim();
                  if (name.isEmpty) {
                    showAppSnackBar('Loo Name cannot be empty', isError: true);
                    return;
                  }
                  if (name.length < 5) {
                    showAppSnackBar(
                      "Please enter a proper name like 'Clock Tower Public Toilet'",
                      isError: true,
                    );
                    return;
                  }

                  String resolvedAddress =
                      '${_selectedAddCoords.latitude.toStringAsFixed(4)}, ${_selectedAddCoords.longitude.toStringAsFixed(4)}';
                  try {
                    final placemarks = await placemarkFromCoordinates(
                      _selectedAddCoords.latitude,
                      _selectedAddCoords.longitude,
                    ).timeout(const Duration(seconds: 5));
                    if (placemarks.isNotEmpty) {
                      final p = placemarks.first;
                      final parts = [
                        p.street,
                        p.subLocality,
                        p.locality,
                      ].where((s) => s != null && s.isNotEmpty).toList();
                      if (parts.isNotEmpty) resolvedAddress = parts.join(', ');
                    }
                  } catch (_) {
                    /* keep coordinate fallback */
                  }

                  // Truth V2 submission. NO fabricated legacy defaults:
                  //  - `is_open` is NOT written — "open right now" is a
                  //    condition observation, not a facility fact.
                  //  - NO top-level `category` / `gender_type` — identity
                  //    (context + gender) lives in `truth_v2` with an explicit
                  //    "unknown", so `Toilet.fromFirestore`'s compatibility
                  //    default ('govt' / 'unisex') can never become truth.
                  //  - fee + amenities are the explicit `truth_v2` block, with
                  //    UNKNOWN serialised as "unknown" (never by omission).
                  //  - No `star_rating` / `total_ratings` mirror.
                  final Map<String, dynamic> data = {
                    'name': name,
                    'address': resolvedAddress,
                    'latitude': _selectedAddCoords.latitude,
                    'longitude': _selectedAddCoords.longitude,
                    'landmark': _addLandmarkController.text.trim(),
                    'added_by': widget.userId,
                    'created_at': FieldValue.serverTimestamp(),
                    // The pure `truth_v2` fields come from
                    // shauchmap_core; the `recorded_at` server sentinel is added
                    // by the Android write adapter. Byte-identical to the
                    // legacy in-app `ToiletTruth.newSubmission(...)` output.
                    'truth_v2': truthV2SubmissionMap(
                      fee: _fee,
                      context: _context,
                      gender: _gender,
                      amenities: ToiletAmenities(
                        water: _water,
                        soap: _soap,
                        lock: _lock,
                        western: _western,
                        wheelchair: _wheelchair,
                        babyChange: _babyChange,
                        sanitaryDisposal: _sanitaryDisposal,
                      ),
                    ),
                  };

                  try {
                    await widget.firestoreService.addToilet(data);
                    await widget.firestoreService.addScoutPoints(
                      widget.userId,
                      50,
                    );
                    await widget.firestoreService.unlockBadge(
                      widget.userId,
                      'first_scout',
                    );

                    try {
                      final snapshot = await FirebaseFirestore.instance
                          .collection('toilets')
                          .count()
                          .get();
                      if (mounted)
                        setState(() => _totalToiletCount = snapshot.count ?? 0);
                    } catch (_) {}

                    fbus.Feedback.fire(fbus.FeedbackEvent.confirm);

                    if (mounted) {
                      setState(() {
                        _addWizardStep = 5;
                        _showBadge = true;
                      });
                      _badgeController.forward();
                    }
                  } catch (e) {
                    if (!mounted) return;
                    CustomHapticsService.playHollowDecay();
                    showAppSnackBar(
                      'Error submitting details: $e',
                      isError: true,
                    );
                  }
                },
              ),
              const SizedBox(height: SmTokens.s8),
              Text(
                'Only location is required',
                style: SmText.caption.copyWith(color: context.sm.ink3),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleCloseRequest();
      },
      child: Scaffold(
        backgroundColor: context.sm.bg,
        body: Stack(
          alignment: Alignment.center,
          children: [
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 20.0,
                      right: 20.0,
                      top: 12.0,
                      bottom: 8.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 28.0),
                        if (_addWizardStep != 5)
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: context.sm.brandSolid,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: SmTokens.s8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: context.sm.soft,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: SmTokens.s8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: context.sm.soft,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            "Success",
                            style: SmText.title.copyWith(color: context.sm.ink),
                          ),
                        if (_addWizardStep != 5)
                          GestureDetector(
                            onTap: _handleCloseRequest,
                            child: Icon(
                              Icons.close,
                              color: context.sm.ink,
                              size: 24.0,
                            ),
                          )
                        else
                          const SizedBox(width: 24.0),
                      ],
                    ),
                  ),
                  Divider(color: context.sm.line, height: 1.0),
                  Expanded(child: _buildAddWizardContent()),
                ],
              ),
            ),
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
                          color: context.sm.brandSolid,
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
                          "+50 XP",
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
        ),
      ),
    );
  }
}

/// A compact segmented picker used for Truth V2 three-state inputs (fee,
/// amenities). Every option shows a WORD, not colour alone (HARD_RULES #10).
class _Segmented<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SmTokens.rPill),
        border: Border.all(color: c.line, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (opt, label) in options)
            GestureDetector(
              onTap: () => onChanged(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                constraints: const BoxConstraints(minHeight: 40, minWidth: 52),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: SmTokens.s12,
                  vertical: SmTokens.s8,
                ),
                decoration: BoxDecoration(
                  color: value == opt
                      ? c.brandSolid.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(SmTokens.rPill),
                  border: Border.all(
                    color: value == opt ? c.brandSolid : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  label,
                  style: SmText.caption.copyWith(
                    color: value == opt ? c.brand : c.ink2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
