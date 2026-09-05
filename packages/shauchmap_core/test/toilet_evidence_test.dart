// Evidence V2 client model — verifies ABSENT / INDEXED-ZERO /
// INDEXED-NONZERO, STRICT per-section parsing (a malformed section => not
// available, without invalidating valid siblings), and passive time expiry.

import 'package:shauchmap_core/shauchmap_core.dart';
import 'package:test/test.dart';

Instant _ts(DateTime d) => Instant.fromDateTime(d);
final _now = DateTime(2026, 9, 2, 12, 0, 0);
final _srvStamps = {
  'computed_at': _ts(_now.subtract(const Duration(seconds: 5))),
  'last_event_at': _ts(_now.subtract(const Duration(seconds: 6))),
};

ToiletEvidence _ev(Map<String, dynamic> inner) =>
    ToiletEvidence.fromFirestore({'version': 1, ...inner});

void main() {
  group('whole map', () {
    test('null / non-map => unavailable', () {
      final e = ToiletEvidence.fromFirestore(null);
      expect(e.present, isFalse);
      expect(e.ratings.available, isFalse);
      expect(e.votes.available, isFalse);
      expect(e.condition.available, isFalse);
    });

    test('wrong version => whole thing unavailable', () {
      final e = ToiletEvidence.fromFirestore({
        'version': 2,
        'ratings': {'count': 3, 'average': 3, ..._srvStamps},
      });
      expect(e.present, isFalse);
      expect(e.ratings.available, isFalse);
    });

    test('lazily-created: only some sections present is fine', () {
      final e = _ev({
        'ratings': {'count': 0, 'average': null, ..._srvStamps},
      });
      expect(e.present, isTrue);
      expect(e.ratings.available, isTrue);
      expect(e.votes.available, isFalse); // absent
      expect(e.condition.available, isFalse); // absent
    });
  });

  group('ratings — STRICT', () {
    test('absent => unavailable, NOT zero', () {
      final r = _ev({}).ratings;
      expect(r.available, isFalse);
      expect(r.isIndexedZero, isFalse);
    });
    test('indexed zero (count 0 + null average) => available', () {
      final r = _ev({
        'ratings': {'count': 0, 'average': null, ..._srvStamps},
      }).ratings;
      expect(r.available, isTrue);
      expect(r.isIndexedZero, isTrue);
    });
    test('indexed nonzero in [1,5] => available', () {
      final r = _ev({
        'ratings': {'count': 4, 'average': 3.75, ..._srvStamps},
      }).ratings;
      expect(r.available, isTrue);
      expect(r.count, 4);
      expect(r.average, 3.75);
    });
    test('negative count => unavailable', () {
      expect(
        _ev({
          'ratings': {'count': -1, 'average': null, ..._srvStamps},
        }).ratings.available,
        isFalse,
      );
    });
    test('count 0 with a non-null average => unavailable (inconsistent)', () {
      expect(
        _ev({
          'ratings': {'count': 0, 'average': 4.0, ..._srvStamps},
        }).ratings.available,
        isFalse,
      );
    });
    test('count > 0 with a null average => unavailable', () {
      expect(
        _ev({
          'ratings': {'count': 3, 'average': null, ..._srvStamps},
        }).ratings.available,
        isFalse,
      );
    });
    test('average > 5 or < 1 => unavailable', () {
      expect(
        _ev({
          'ratings': {'count': 3, 'average': 5.4, ..._srvStamps},
        }).ratings.available,
        isFalse,
      );
      expect(
        _ev({
          'ratings': {'count': 3, 'average': 0.5, ..._srvStamps},
        }).ratings.available,
        isFalse,
      );
    });
    test('missing computed_at / last_event_at => unavailable', () {
      expect(
        _ev({
          'ratings': {'count': 2, 'average': 3, 'last_event_at': _ts(_now)},
        }).ratings.available,
        isFalse,
      );
      expect(
        _ev({
          'ratings': {'count': 2, 'average': 3, 'computed_at': _ts(_now)},
        }).ratings.available,
        isFalse,
      );
    });
    test(
      'a malformed ratings section does NOT invalidate a valid votes sibling',
      () {
        final e = _ev({
          'ratings': {'count': -5},
          'votes': {'up': 2, 'down': 1, ..._srvStamps},
        });
        expect(e.ratings.available, isFalse);
        expect(e.votes.available, isTrue);
        expect(e.votes.up, 2);
      },
    );
  });

  group('votes — STRICT', () {
    test('absent => unavailable', () {
      expect(_ev({}).votes.available, isFalse);
    });
    test('indexed 0/0 => available (never a ratio)', () {
      final v = _ev({
        'votes': {'up': 0, 'down': 0, ..._srvStamps},
      }).votes;
      expect(v.available, isTrue);
      expect(v.isIndexedZero, isTrue);
    });
    test('negative up/down => unavailable', () {
      expect(
        _ev({
          'votes': {'up': -1, 'down': 0, ..._srvStamps},
        }).votes.available,
        isFalse,
      );
      expect(
        _ev({
          'votes': {'up': 0, 'down': -3, ..._srvStamps},
        }).votes.available,
        isFalse,
      );
    });
    test('non-int up => unavailable', () {
      expect(
        _ev({
          'votes': {'up': 1.5, 'down': 0, ..._srvStamps},
        }).votes.available,
        isFalse,
      );
    });
    test('missing server stamps => unavailable', () {
      expect(
        _ev({
          'votes': {'up': 1, 'down': 0},
        }).votes.available,
        isFalse,
      );
    });
  });

  group('condition — STRICT + passive expiry', () {
    Map<String, int> supFor(Object? verdict, int cc) => switch (verdict) {
          'yes' => {'yes': cc, 'no': 0, 'unknown': 0},
          'no' => {'yes': 0, 'no': cc, 'unknown': 0},
          _ => {'yes': 0, 'no': 0, 'unknown': cc},
        };

    Map<String, dynamic> cond(Map<String, dynamic> over) {
      final m = <String, dynamic>{
        'open': 'unknown',
        'water': 'unknown',
        'usable': 'unknown',
        'lock': 'unknown',
        'contributor_count': 0,
        ..._srvStamps,
        ...over,
      };
      // Build a consistent support block (sum == contributor_count) unless the
      // caller supplied one explicitly.
      m['support'] ??= {
        for (final d in ['open', 'water', 'usable', 'lock'])
          d: supFor(m[d], (m['contributor_count'] as num).toInt()),
      };
      return m;
    }

    test('absent => unavailable', () {
      expect(_ev({}).condition.available, isFalse);
    });
    test('a bad tri-state value => unavailable', () {
      expect(
        _ev({
          'condition': cond({'open': 'maybe', 'contributor_count': 1}),
        }).condition.available,
        isFalse,
      );
    });
    test('missing a tri-state field => unavailable', () {
      final c = {
        'water': 'unknown',
        'usable': 'unknown',
        'lock': 'unknown',
        'contributor_count': 1,
        ..._srvStamps,
      };
      expect(_ev({'condition': c}).condition.available, isFalse);
    });
    test('negative contributor_count => unavailable', () {
      expect(
        _ev({
          'condition': cond({'contributor_count': -2}),
        }).condition.available,
        isFalse,
      );
    });
    test('missing server stamps => unavailable', () {
      final c = {
        'open': 'yes',
        'water': 'unknown',
        'usable': 'unknown',
        'lock': 'unknown',
        'contributor_count': 1,
        'latest_at': _ts(_now),
        'valid_until': _ts(_now.add(const Duration(minutes: 30))),
      };
      expect(_ev({'condition': c}).condition.available, isFalse);
    });
    test('contributor_count 0 with a non-unknown verdict => unavailable', () {
      expect(
        _ev({
          'condition': cond({'open': 'yes', 'contributor_count': 0}),
        }).condition.available,
        isFalse,
      );
    });
    test('contributor_count 0 with a valid_until => unavailable', () {
      expect(
        _ev({
          'condition': cond({
            'contributor_count': 0,
            'valid_until': _ts(_now.add(const Duration(minutes: 10))),
          }),
        }).condition.available,
        isFalse,
      );
    });
    test(
      'contributor_count 0, all unknown, no windows => available & never valid',
      () {
        final c = _ev({'condition': cond({})}).condition;
        expect(c.available, isTrue);
        expect(c.validUntil, isNull);
        expect(c.isCurrentlyValid(_now), isFalse);
      },
    );
    test('contributor_count > 0 missing valid_until => unavailable', () {
      expect(
        _ev({
          'condition': cond({
            'open': 'yes',
            'contributor_count': 2,
            'latest_at': _ts(_now.subtract(const Duration(minutes: 5))),
          }),
        }).condition.available,
        isFalse,
      );
    });
    test('contributor_count > 0 missing latest_at => unavailable', () {
      expect(
        _ev({
          'condition': cond({
            'open': 'yes',
            'contributor_count': 2,
            'valid_until': _ts(_now.add(const Duration(minutes: 40))),
          }),
        }).condition.available,
        isFalse,
      );
    });
    test('valid summary, not yet expired', () {
      final c = _ev({
        'condition': cond({
          'open': 'yes',
          'usable': 'yes',
          'contributor_count': 2,
          'latest_at': _ts(_now.subtract(const Duration(minutes: 10))),
          'valid_until': _ts(_now.add(const Duration(minutes: 50))),
        }),
      }).condition;
      expect(c.available, isTrue);
      expect(c.open, ConditionState.yes);
      expect(c.isCurrentlyValid(_now), isTrue);
      expect(c.ageMinutes(_now), 10);
    });
    test('EXPIRED: isCurrentlyValid false once now >= validUntil', () {
      final vu = _now.add(const Duration(minutes: 1));
      final c = _ev({
        'condition': cond({
          'open': 'yes',
          'contributor_count': 3,
          'latest_at': _ts(_now.subtract(const Duration(minutes: 1))),
          'valid_until': _ts(vu),
        }),
      }).condition;
      expect(c.open, ConditionState.yes); // still stored
      expect(
        c.isCurrentlyValid(vu.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(c.isCurrentlyValid(vu), isFalse);
      expect(c.isCurrentlyValid(vu.add(const Duration(minutes: 5))), isFalse);
    });

    // ---- support-count validation ----
    Map<String, dynamic> valid2(Map<String, dynamic> supportOver) => cond({
          'open': 'yes',
          'usable': 'yes',
          'contributor_count': 2,
          'latest_at': _ts(_now.subtract(const Duration(minutes: 5))),
          'valid_until': _ts(_now.add(const Duration(minutes: 40))),
          'support': {
            'open': {'yes': 2, 'no': 0, 'unknown': 0},
            'water': {'yes': 0, 'no': 0, 'unknown': 2},
            'usable': {'yes': 2, 'no': 0, 'unknown': 0},
            'lock': {'yes': 0, 'no': 0, 'unknown': 2},
            ...supportOver,
          },
        });

    test('valid support block => available + parsed counts', () {
      final c = _ev({'condition': valid2({})}).condition;
      expect(c.available, isTrue);
      expect(c.supportUsable.yes, 2);
      expect(c.supportUsable.total, 2);
      expect(c.supportWater.unknown, 2);
    });
    test('missing support block entirely => unavailable', () {
      final c = {
        'open': 'yes',
        'water': 'unknown',
        'usable': 'yes',
        'lock': 'unknown',
        'contributor_count': 2,
        'latest_at': _ts(_now.subtract(const Duration(minutes: 5))),
        'valid_until': _ts(_now.add(const Duration(minutes: 40))),
        ..._srvStamps,
      };
      expect(_ev({'condition': c}).condition.available, isFalse);
    });
    test('missing one support dimension => unavailable', () {
      final s = {
        'open': {'yes': 2, 'no': 0, 'unknown': 0},
        'water': {'yes': 0, 'no': 0, 'unknown': 2},
        'usable': {'yes': 2, 'no': 0, 'unknown': 0},
        // no 'lock'
      };
      final c = {...valid2({}), 'support': s};
      expect(_ev({'condition': c}).condition.available, isFalse);
    });
    test('support sum != contributor_count => unavailable', () {
      expect(
        _ev({
          'condition': valid2({
            'usable': {'yes': 1, 'no': 0, 'unknown': 0}, // sums to 1, cc is 2
          }),
        }).condition.available,
        isFalse,
      );
    });
    test('negative support value => unavailable', () {
      expect(
        _ev({
          'condition': valid2({
            'open': {'yes': 3, 'no': -1, 'unknown': 0},
          }),
        }).condition.available,
        isFalse,
      );
    });
    test('non-int support value => unavailable', () {
      expect(
        _ev({
          'condition': valid2({
            'open': {'yes': 2.0, 'no': 0, 'unknown': 0},
          }),
        }).condition.available,
        isFalse,
      );
    });

    // ---- declared verdict must equal support-implied verdict.
    test(
      'verdict "yes" contradicted by support {yes:0,no:2} => unavailable',
      () {
        expect(
          _ev({
            'condition': valid2({
              'usable': {'yes': 0, 'no': 2, 'unknown': 0}, // implies "no"
            }),
          }).condition.available,
          isFalse,
        );
      },
    );
    test(
        'verdict "yes" contradicted by a TIE support {yes:1,no:1} => '
        'unavailable', () {
      expect(
        _ev({
          'condition': valid2({
            'open': {'yes': 1, 'no': 1, 'unknown': 0}, // tie implies "unknown"
          }),
        }).condition.available,
        isFalse,
      );
    });
    test(
        'verdict "unknown" contradicted by support {yes:2,no:0} => '
        'unavailable', () {
      final c = cond({
        'open': 'yes',
        'water': 'unknown', // declared unknown ...
        'usable': 'yes',
        'contributor_count': 2,
        'latest_at': _ts(_now.subtract(const Duration(minutes: 5))),
        'valid_until': _ts(_now.add(const Duration(minutes: 40))),
        'support': {
          'open': {'yes': 2, 'no': 0, 'unknown': 0},
          'water': {'yes': 2, 'no': 0, 'unknown': 0}, // ... but implies "yes"
          'usable': {'yes': 2, 'no': 0, 'unknown': 0},
          'lock': {'yes': 0, 'no': 0, 'unknown': 2},
        },
      });
      expect(_ev({'condition': c}).condition.available, isFalse);
    });
    test(
      'a consistent "no" verdict with {yes:0,no:2} support => available',
      () {
        final c = cond({
          'open': 'no',
          'usable': 'no',
          'contributor_count': 2,
          'latest_at': _ts(_now.subtract(const Duration(minutes: 5))),
          'valid_until': _ts(_now.add(const Duration(minutes: 40))),
          'support': {
            'open': {'yes': 0, 'no': 2, 'unknown': 0},
            'water': {'yes': 0, 'no': 0, 'unknown': 2},
            'usable': {'yes': 0, 'no': 2, 'unknown': 0},
            'lock': {'yes': 0, 'no': 0, 'unknown': 2},
          },
        });
        final ce = _ev({'condition': c}).condition;
        expect(ce.available, isTrue);
        expect(ce.open, ConditionState.no);
        expect(ce.usable, ConditionState.no);
      },
    );
  });
}
