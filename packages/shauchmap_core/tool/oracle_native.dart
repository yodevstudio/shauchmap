// Runs oracle/vectors.json through the shared core's canonical JSON API
// (NATIVE Dart) and writes oracle/native_result.json. When --gen is passed it
// ALSO writes oracle/expected.json (the authority; regenerate only deliberately).
import 'dart:convert';
import 'dart:io';
import 'package:shauchmap_core/interop/canonical.dart' as api;

void main(List<String> args) {
  final gen = args.contains('--gen');
  final dir = '${File(Platform.script.toFilePath()).parent.parent.path}/oracle';
  final v = jsonDecode(File('$dir/vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  final nowMs = (v['_nowMs'] as num);

  final out = <String, dynamic>{
    'truth': [
      for (final t in v['truth'])
        {
          'name': t['name'],
          'out': jsonDecode(api.evaluateTruth(jsonEncode(t['map'])))
        }
    ],
    'evidence': [
      for (final e in v['evidence'])
        {
          'name': e['name'],
          'out': jsonDecode(
              api.evaluateEvidence(jsonEncode(e['evidence_v2']), nowMs))
        }
    ],
    'go': [
      for (final g in v['go'])
        {
          'name': g['name'],
          'out': jsonDecode(api.evaluateGo(
              jsonEncode({'pool': g['pool']}), (g['nowMs'] as num)))
        }
    ],
    'revalidation': [
      for (final r in v['revalidation'])
        {
          'name': r['name'],
          'out': jsonDecode(api.evaluateRevalidation(jsonEncode({
            'targetId': r['targetId'],
            'stale': r['stale'],
            'fresh': r['fresh']
          })))
        }
    ],
    'freshness': [
      for (final f in (v['freshness'] as List? ?? const []))
        {
          'name': f['name'],
          'out': jsonDecode(api.evaluatePositionFreshness(jsonEncode({
            'positionTsMs': f['positionTsMs'],
            'nowMs': f['nowMs'],
            'maxAgeSeconds': f['maxAgeSeconds'],
          })))
        }
    ],
    'distances': [
      for (final d in (v['distances'] as List? ?? const []))
        {
          'name': d['name'],
          'out': jsonDecode(api.evaluateDistances(
              jsonEncode({'from': d['from'], 'to': d['to']})))
        }
    ],
    'hint': [
      for (final h in (v['hint'] as List? ?? const []))
        {
          'name': h['name'],
          'out': jsonDecode(api.evaluateGo(
              jsonEncode({'pool': h['pool'], 'hintId': h['hintId']}),
              (h['nowMs'] as num)))
        }
    ],
  };
  const enc = JsonEncoder.withIndent('  ');
  File('$dir/native_result.json').writeAsStringSync(enc.convert(out));
  if (gen) File('$dir/expected.json').writeAsStringSync(enc.convert(out));

  if (!gen && File('$dir/expected.json').existsSync()) {
    final exp =
        jsonDecode(File('$dir/expected.json').readAsStringSync()) as Map;
    var total = 0, pass = 0;
    final fails = <String>[];
    for (final sect in [
      'truth',
      'evidence',
      'go',
      'revalidation',
      'freshness',
      'distances',
      'hint'
    ]) {
      final a = out[sect] as List, b = exp[sect] as List;
      for (var i = 0; i < a.length; i++) {
        total++;
        if (jsonEncode(a[i]['out']) == jsonEncode(b[i]['out'])) {
          pass++;
        } else {
          fails.add('$sect: ${a[i]['name']}');
        }
      }
    }
    stdout.writeln('NATIVE oracle: $pass/$total'
        '${fails.isEmpty ? '' : '  FAILS: ${fails.join('; ')}'}');
    if (pass != total) exitCode = 1;
  } else {
    stdout.writeln('wrote $dir/native_result.json'
        '${gen ? ' + expected.json' : ''}  ('
        '${(out['truth'] as List).length}t '
        '${(out['evidence'] as List).length}e '
        '${(out['go'] as List).length}g '
        '${(out['revalidation'] as List).length}r '
        '${(out['freshness'] as List).length}f '
        '${(out['distances'] as List).length}d '
        '${(out['hint'] as List).length}h)');
  }
}
