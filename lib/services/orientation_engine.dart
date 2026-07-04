class OrientationEngine {
  double _lastHeading = 0.0;
  bool isTrackingUser = true;

  double calculateSmoothedBearing(double hardwareHeading) {
    double targetHeading = hardwareHeading < 0
        ? hardwareHeading + 360
        : hardwareHeading;
    double diff = targetHeading - _lastHeading;
    if (diff.abs() > 180) {
      if (targetHeading > _lastHeading) {
        _lastHeading += 360;
      } else {
        _lastHeading -= 360;
      }
    }
    _lastHeading = _lastHeading + (targetHeading - _lastHeading) * 0.15;
    _lastHeading = _lastHeading % 360;
    return _lastHeading;
  }
}
