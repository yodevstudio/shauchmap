// `dart compile js -O2 -o <out>/core.js tool/interop_entry.dart`
// Installs `globalThis.shauchmapCore` with the 6 String->String domain
// functions + an interop version number. NO Flutter runtime, NO Firebase,
// NO geolocator.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:shauchmap_core/interop/canonical.dart' as api;

void main() {
  final core = JSObject();
  core['evaluateTruth'] =
      ((JSString j) => api.evaluateTruth(j.toDart).toJS).toJS;
  core['evaluateEvidence'] = ((JSString j, JSNumber nowMs) =>
      api.evaluateEvidence(j.toDart, nowMs.toDartDouble).toJS).toJS;
  core['evaluateGo'] = ((JSString j, JSNumber nowMs) =>
      api.evaluateGo(j.toDart, nowMs.toDartDouble).toJS).toJS;
  core['evaluateRevalidation'] =
      ((JSString j) => api.evaluateRevalidation(j.toDart).toJS).toJS;
  core['evaluatePositionFreshness'] =
      ((JSString j) => api.evaluatePositionFreshness(j.toDart).toJS).toJS;
  core['evaluateDistances'] =
      ((JSString j) => api.evaluateDistances(j.toDart).toJS).toJS;
  core['interopVersion'] = api.kCoreInteropVersion.toJS;
  core['version'] = '8.1.1-shared-core'.toJS;
  globalContext['shauchmapCore'] = core;
}
