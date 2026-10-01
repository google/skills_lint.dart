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
      writeFixture(tempDir.path, 5);
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
