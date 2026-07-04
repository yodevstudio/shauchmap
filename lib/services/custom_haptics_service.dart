import 'package:flutter/services.dart';

class CustomHapticsService {
  static const MethodChannel _channel = MethodChannel(
    'com.shauchmap.app/haptics',
  );

  // ==========================================
  // MAXIMUM INTENSITY HARDWARE OVERRIDES
  // ==========================================

  /// Smooth gear-like friction for star sliders (Heavy kinetic click)
  static Future<void> playStarScroll() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 25],
        'amplitudes': [0, 200],
      });
    } catch (_) {}
  }

  /// Structural lock for integer star milestones (Maximum hardware snap)
  static Future<void> playStarLock() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 40],
        'amplitudes': [0, 255],
      });
    } catch (_) {}
  }

  /// Directional choice feedback (ON is sharp, OFF is dull)
  static Future<void> playAsymmetricChoice(bool isChecking) async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': isChecking ? [0, 30] : [0, 20],
        'amplitudes': isChecking ? [0, 255] : [0, 100],
      });
    } catch (_) {}
  }

  /// Map boundary rubber-band effect (Heavy double thud)
  static Future<void> playRubberBandBounce() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 40, 30, 50],
        'amplitudes': [0, 255, 0, 180],
      });
    } catch (_) {}
  }

  /// High-tier success composition (Duolingo level-up cascade)
  static Future<void> playRewardCrescendo() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 30, 40, 30, 40, 50, 30, 80],
        'amplitudes': [0, 100, 0, 150, 0, 200, 0, 255],
      });
    } catch (_) {}
  }

  /// Hollow double-pulse exit feedback (Error state)
  static Future<void> playHollowDecay() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 50, 30, 40],
        'amplitudes': [0, 200, 0, 80],
      });
    } catch (_) {}
  }

  static Future<void> playCrispSuccess() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 30, 40, 30],
        'amplitudes': [0, 150, 0, 255],
      });
    } catch (_) {}
  }

  static Future<void> playSpringBounce() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 20, 20, 20, 20, 20],
        'amplitudes': [0, 200, 120, 60, 30, 0],
      });
    } catch (_) {}
  }

  static Future<void> playSoftTick() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 15],
        'amplitudes': [0, 120],
      });
    } catch (_) {}
  }

  static Future<void> playCardSnap() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 20],
        'amplitudes': [0, 160],
      });
    } catch (_) {}
  }

  static Future<void> playToggle(bool isOn) async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': isOn ? [0, 20] : [0, 15],
        'amplitudes': isOn ? [0, 180] : [0, 90],
      });
    } catch (_) {}
  }

  static Future<void> playStarFill(int starValue) async {
    try {
      int intensity = (starValue * 50).clamp(50, 255);
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 20],
        'amplitudes': [0, intensity],
      });
    } catch (_) {}
  }

  static Future<void> playStepTransition() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 15, 40, 20],
        'amplitudes': [0, 160, 0, 220],
      });
    } catch (_) {}
  }

  static Future<void> playTileSelect() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 30],
        'amplitudes': [0, 255],
      });
    } catch (_) {}
  }

  static Future<void> playToggleSnap() async {
    try {
      await _channel.invokeMethod('playWaveform', {
        'timings': [0, 15],
        'amplitudes': [0, 140],
      });
    } catch (_) {}
  }
}
