import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

class LooSprings {
  static const SpringDescription snappy = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 28,
  );

  static const SpringDescription bouncy = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 18,
  );

  static const SpringDescription gentle = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 26,
  );
}

extension SpringAnimationController on AnimationController {
  Future<void> springTo(
    double target, {
    required SpringDescription spring,
    double velocity = 0,
  }) {
    final simulation = SpringSimulation(spring, value, target, velocity);
    return animateWith(simulation).orCancel.catchError((_) {});
  }
}
