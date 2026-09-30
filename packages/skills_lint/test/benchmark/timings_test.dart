// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:test/test.dart';

import '../../benchmark/src/fixture.dart';
import '../../benchmark/src/timings.dart';

void main() {
  _timedRuleConfigsTests();
  _loopsForTests();
  _findSkillDirectoriesTests();
  _compareTimingsTests();
  _timingsMarkdownTests();
  _jsonTests();
  _timeRulesTests();
}

void _timedRuleConfigsTests() {
  group('timedRuleConfigs', () {
    test('turns on every registered rule, so the benchmarks time each rule', () {
      final Set<String> enabled = {
        for (final rule in Validator(ruleConfigs: timedRuleConfigs()).rules) rule.name,
      };
      final List<String> missing = [
        for (final check in RuleRegistry.allChecks)
          if (!enabled.contains(check.name)) check.name,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'Add these rules to fixtureConfig in benchmark/src/fixture.dart so that the '
            'macro benchmark and the rule timings cover them: $missing',
      );
    });

    test('throws on a configuration that does not parse', () {
      expect(() => timedRuleConfigs('skills_lint: [1, 2]'), throwsStateError);
    });
  });
}

void _loopsForTests() {
  group('loopsFor', () {
    test('repeats a small corpus to reach the minimum number of visits', () {
      expect(loopsFor(36), 28);
      expect(loopsFor(minimumSkillVisits), 1);
      expect(loopsFor(minimumSkillVisits * 3), 1);
    });

    test('rejects an empty corpus', () {
      expect(() => loopsFor(0), throwsArgumentError);
    });
  });
}

void _findSkillDirectoriesTests() {
  group('findSkillDirectories', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('timings_test.'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('finds nested skills under each root, sorted, and skips missing roots', () {
      for (final dir in ['b/skill-two', 'a/nested/skill-one', 'b/not-a-skill']) {
        Directory(p.join(tempDir.path, dir)).createSync(recursive: true);
      }
      File(p.join(tempDir.path, 'b', 'skill-two', 'SKILL.md')).writeAsStringSync('');
      File(p.join(tempDir.path, 'a', 'nested', 'skill-one', 'SKILL.md')).writeAsStringSync('');
      File(p.join(tempDir.path, 'b', 'not-a-skill', 'README.md')).writeAsStringSync('');

      final List<Directory> found = findSkillDirectories([
        p.join(tempDir.path, 'b'),
        p.join(tempDir.path, 'missing'),
        p.join(tempDir.path, 'a'),
      ]);

      expect(
        [for (final d in found) p.relative(d.path, from: tempDir.path)],
        [p.join('a', 'nested', 'skill-one'), p.join('b', 'skill-two')],
      );
    });
  });
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
          ('costly', RuleStatus.measured, 75.0),
          ('brand-new', RuleStatus.measured, 22.5),
          ('cheap', RuleStatus.measured, 2.5),
        ],
      );
    });

    test('marks rules only in the candidate as added and only in the baseline as removed', () {
      final List<RuleTimingRow> rows = compareTimings(candidate, baseline: baseline);

      expect(
        [for (final r in rows) (r.rule, r.status, r.change)],
        [
          ('costly', RuleStatus.measured, 50.0),
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

void _jsonTests() {
  test('CorpusTimings survives a JSON round trip', () {
    const timings = CorpusTimings(
      corpus: 'real',
      skillCount: 36,
      rules: {
        'a-rule': [1.5, 2.25],
      },
    );

    final Object? decoded = jsonDecode(jsonEncode(timings.toJson()));
    final CorpusTimings read = CorpusTimings.fromJson(decoded! as Map<String, Object?>);

    expect(read.corpus, 'real');
    expect(read.skillCount, 36);
    expect(read.rules, {
      'a-rule': [1.5, 2.25],
    });
  });
}

void _timeRulesTests() {
  group('timeRules', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('timings_test.'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('takes one sample per repetition for each rule of the validator', () async {
      writeFixture(tempDir.path, const FixtureSpec(skillCount: 5));
      final List<Directory> dirs = findSkillDirectories([
        p.join(tempDir.path, skillsDirectoryName),
      ]);
      final validator = Validator(ruleConfigs: timedRuleConfigs());

      final CorpusTimings timings = await timeRules(
        'fixture',
        dirs,
        validator,
        warmup: 1,
        repetitions: 2,
      );

      expect(timings.skillCount, 5);
      expect(timings.rules.keys, [for (final rule in validator.rules) rule.name]);
      for (final MapEntry(key: rule, value: samples) in timings.rules.entries) {
        expect(samples, hasLength(2), reason: rule);
        expect(samples, everyElement(greaterThanOrEqualTo(0)), reason: rule);
      }
    });
  });
}
