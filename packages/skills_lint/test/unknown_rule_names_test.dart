// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/unknown_rule_names.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

/// Collects what is written to it, for use as `stderr` in [IOOverrides].
class _CapturingStdout implements Stdout {
  final StringBuffer buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  Future<void> flush() async {}

  /// Throws for any other member, so a test fails loudly if validation starts
  /// using one.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A custom rule named [name] that never reports anything.
class _QuietCustomRule extends SkillRule {
  _QuietCustomRule([this.name = 'my-team-rule']);

  @override
  final String name;

  @override
  final AnalysisSeverity severity = AnalysisSeverity.warning;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => const [];
}

final String validSkillPath = p.normalize(p.absolute(p.join('example', 'skills', 'valid')));

void main() {
  group('unknownRuleNameWarnings', () {
    test('names a misspelled rule and suggests the closest rule', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

      expect(config.parsingErrors, isEmpty);
      expect(unknownRuleNameWarnings(config, const []), [
        'Global rules: Unknown rule "check-relative-path". Did you mean "check-relative-paths"?',
      ]);
    });

    test('names an unknown rule without a suggestion when nothing is close', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    no-such-rule-at-all: error
''');

      expect(unknownRuleNameWarnings(config, const []), [
        'Global rules: Unknown rule "no-such-rule-at-all".',
      ]);
    });

    test('checks the rules of directory and individual skill entries', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  directories:
    - path: skills
      rules:
        check-relative-path: error
  individual_skills:
    - path: one/skill
      rules:
        bogus-rule-name-here: error
''');

      expect(unknownRuleNameWarnings(config, const []), [
        'Directory entry rules for "skills": Unknown rule "check-relative-path". Did you mean "check-relative-paths"?',
        'Individual skill entry rules for "one/skill": Unknown rule "bogus-rule-name-here".',
      ]);
    });

    test('does not flag a custom rule or its parameters', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    my-team-rule:
      severity: error
      threshold: 3
''');

      expect(config.parsingErrors, isEmpty);
      expect(unknownRuleNameWarnings(config, [_QuietCustomRule()]), isEmpty);
    });

    test('suggests a custom rule for a misspelling of it', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    my-team-rul: error
''');

      expect(unknownRuleNameWarnings(config, [_QuietCustomRule()]), [
        'Global rules: Unknown rule "my-team-rul". Did you mean "my-team-rule"?',
      ]);
    });

    test('suggests nothing when two rules are equally close', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    team-rule-c: error
''');

      expect(
        unknownRuleNameWarnings(config, [
          _QuietCustomRule('team-rule-a'),
          _QuietCustomRule('team-rule-b'),
        ]),
        ['Global rules: Unknown rule "team-rule-c".'],
      );
    });

    test('does not flag any built-in rule', () {
      final config = Configuration(
        ruleConfigs: {
          for (final check in RuleRegistry.allChecks)
            check.name: const RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      );

      expect(unknownRuleNameWarnings(config, const []), isEmpty);
    });
  });

  group('validateSkills with an unknown rule name', () {
    Future<(bool, String)> validate(String yaml, {List<SkillRule> customRules = const []}) async {
      final Configuration config = ConfigParser.parse(yaml);
      final err = _CapturingStdout();
      final bool passed = await IOOverrides.runZoned(
        () => validateSkills(
          individualSkillPaths: [validSkillPath],
          config: config,
          customRules: customRules,
          quiet: true,
        ),
        stderr: () => err,
      );
      return (passed, err.buffer.toString());
    }

    test('prints a warning with a suggestion and passes', () async {
      final (bool passed, String err) = await validate('''
skills_lint:
  rules:
    check-relative-path: error
''');

      expect(
        err,
        contains(
          'Configuration warning: Global rules: Unknown rule "check-relative-path". '
          'Did you mean "check-relative-paths"?',
        ),
      );
      expect(passed, isTrue);
    });

    test('prints no warning for a custom rule passed in customRules', () async {
      final (bool passed, String err) = await validate(
        '''
skills_lint:
  rules:
    my-team-rule: error
''',
        customRules: [_QuietCustomRule()],
      );

      expect(err, isNot(contains('Configuration warning')));
      expect(passed, isTrue);
    });
  });

  group('skills_lint command with an unknown rule name', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('unknown_rule_test.');
      final Directory skillDir = await Directory(
        p.join(tempDir.path, 'skills', 'my-skill'),
      ).create(recursive: true);
      await File(
        p.join(skillDir.path, 'SKILL.md'),
      ).writeAsString('${buildFrontmatter(name: 'my-skill')}Body\n');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('prints a warning with a suggestion and exits 0', () async {
      await File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
skills_lint:
  directories:
    - path: skills
  rules:
    check-relative-path: error
''');

      final TestProcess process = await startCli([], workingDirectory: tempDir.path);

      await process.shouldExit(0);
      final String err = (await process.stderr.rest.toList()).join('\n');
      expect(
        err,
        contains(
          'Configuration warning: Global rules: Unknown rule "check-relative-path". '
          'Did you mean "check-relative-paths"?',
        ),
      );
    });

    test('keeps JSON output on stdout parseable', () async {
      await File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
skills_lint:
  directories:
    - path: skills
  rules:
    check-relative-path: error
''');

      final TestProcess process = await startCli(['--format=json'], workingDirectory: tempDir.path);

      await process.shouldExit(0);
      final String out = (await process.stdout.rest.toList()).join('\n');
      expect(() => jsonDecode(out), returnsNormally);
      expect(out, isNot(contains('Configuration warning')));
      final String err = (await process.stderr.rest.toList()).join('\n');
      expect(err, contains('Unknown rule "check-relative-path"'));
    });

    test('prints no warning with --ignore-config', () async {
      await File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
skills_lint:
  rules:
    check-relative-path: error
''');

      final TestProcess process = await startCli([
        '--ignore-config',
        '-d',
        p.join(tempDir.path, 'skills'),
      ], workingDirectory: tempDir.path);

      await process.shouldExit(0);
      final String err = (await process.stderr.rest.toList()).join('\n');
      expect(err, isNot(contains('Configuration warning')));
    });

    test('prints no warning for known rule names', () async {
      await File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
skills_lint:
  directories:
    - path: skills
  rules:
    check-relative-paths: error
''');

      final TestProcess process = await startCli([], workingDirectory: tempDir.path);

      await process.shouldExit(0);
      final String err = (await process.stderr.rest.toList()).join('\n');
      expect(err, isNot(contains('Configuration warning')));
    });
  });
}
