// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../benchmark/src/timings.dart';
import '../../benchmark/src/timings_report.dart';

void main() {
  _compareTimingsTests();
  _timingsMarkdownTests();
}

void _compareTimingsTests() {
  group('compareTimings', () {
    const candidate = CorpusTimings(
      corpus: 'fixture',
      skillCount: 10,
      rules: {
        'cheap': [1, 1, 1],
        'costly': [30, 30, 30],
        'brand-new': [9, 9, 9],
      },
    );
    const baseline = CorpusTimings(
      corpus: 'fixture',
      skillCount: 10,
      rules: {
        'cheap': [1, 1, 1],
        'costly': [20, 20, 20],
        'retired': [5, 5, 5],
      },
    );

    test('without a baseline, lists every rule, costliest first, with its share', () {
      final List<RuleTimingRow> rows = compareTimings(candidate);

      expect(
        [for (final r in rows) (r.rule, r.status, r.share)],
        [
          ('costly', RuleStatus.measured, 0.75),
          ('brand-new', RuleStatus.measured, 0.225),
          ('cheap', RuleStatus.measured, 0.025),
        ],
      );
    });

    test('marks rules only in the candidate as added and only in the baseline as removed', () {
      final List<RuleTimingRow> rows = compareTimings(candidate, baseline: baseline);

      expect(
        [for (final r in rows) (r.rule, r.status, r.change)],
        [
          ('costly', RuleStatus.measured, 0.5),
          ('brand-new', RuleStatus.added, null),
          ('cheap', RuleStatus.measured, 0.0),
          ('retired', RuleStatus.removed, null),
        ],
      );
    });
  });
}

void _timingsMarkdownTests() {
  group('timingsMarkdown', () {
    const candidate = CorpusTimings(
      corpus: 'fixture',
      skillCount: 10,
      rules: {
        'a-rule': [2, 2, 2],
        'new-rule': [6, 6, 6],
      },
    );

    test('flags a rule that the baseline lacks as a new rule', () {
      final String markdown = timingsMarkdown(
        [candidate],
        baseline: [
          const CorpusTimings(
            corpus: 'fixture',
            skillCount: 10,
            rules: {
              'a-rule': [1, 1, 1],
            },
          ),
        ],
        defaultRules: {'a-rule'},
      );

      expect(markdown, contains('### fixture (10 skills)'));
      expect(markdown, contains('| new-rule | no |  | 6.0 | **new rule** | 75.0% | 0.0% |'));
      expect(markdown, contains('| a-rule | yes | 1.0 | 2.0 | +100.0% | 25.0% | 0.0% |'));
    });

    test('without a baseline, shows one time column', () {
      final String markdown = timingsMarkdown([candidate]);

      expect(markdown, contains('| Rule | On by default | µs/skill | Share | MAD |'));
      expect(markdown, contains('| new-rule | no | 6.0 | 75.0% | 0.0% |'));
    });

    test('says so when the baseline lacks a corpus', () {
      final String markdown = timingsMarkdown([candidate], baseline: const []);

      expect(markdown, contains('The baseline has no timings for this corpus.'));
      expect(markdown, contains('| new-rule | no | 6.0 | 75.0% | 0.0% |'));
    });
  });
}
