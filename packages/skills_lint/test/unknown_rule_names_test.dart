// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/path_utils.dart';
import 'package:skills_lint/src/unknown_rule_names.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('unknownRuleNameMessage', () {
    test('lists every equally close name', () {
      expect(
        unknownRuleNameMessage('check-reloluxe-paths', context: 'Global rules'),
        'Global rules: Unknown rule "check-reloluxe-paths". '
        'Did you mean "check-absolute-paths" or "check-relative-paths"?',
      );
    });

    test('treats skill-file-inaccessible as configurable', () {
      expect(configurableRuleNames, contains('skill-file-inaccessible'));
    });
  });

  group('ConfigParser reports unknown rule names', () {
    test('in the top-level rules, with a suggestion', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

      expect(config.parsingErrors, [
        'Global rules: Unknown rule "check-relative-path". Did you mean "check-relative-paths"?',
      ]);
    });

    test('with a version hint when nothing is close', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    zzz: error
''');

      expect(config.parsingErrors, [
        'Global rules: Unknown rule "zzz". If it is a rule from a newer skills_lint, upgrade skills_lint.',
      ]);
    });

    test('and leaves them out of the configuration', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
    check-absolute-paths: error
''');

      expect(config.ruleConfigs.keys, ['check-absolute-paths']);
      expect(config.toYamlString(), isNot(contains('check-relative-path:')));
    });

    test('with a message of its own for a plain YAML merge key', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    base: &base
      severity: error
    <<: *base
  directories:
    - path: a
      rules:
        "<<": error
''');

      expect(config.parsingErrors, [
        startsWith('Global rules: Unknown rule "base".'),
        'Global rules: YAML merge keys ("<<") are not supported; write out each rule\'s settings.',
        startsWith('Directory entry rules for "a": Unknown rule "<<".'),
      ]);
      expect(config.ruleConfigs, isEmpty);
    });

    test('in target entries', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  directories:
    - path: .agents/skills
      rules:
        valid-yaml-metadat: error
  individual_skills:
    - path: one/skill
      rules:
        check-trailing-whitespac: error
''');

      expect(config.parsingErrors, [
        'Directory entry rules for ".agents/skills": Unknown rule "valid-yaml-metadat". Did you mean "valid-yaml-metadata"?',
        'Individual skill entry rules for "one/skill": Unknown rule "check-trailing-whitespac". Did you mean "check-trailing-whitespace"?',
      ]);
    });

    test('but accepts skill-file-inaccessible', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    skill-file-inaccessible: warning
''');

      expect(config.parsingErrors, isEmpty);
      expect(config.ruleConfigs.keys, ['skill-file-inaccessible']);
    });

    test('including custom rule names, which configuration does not affect', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    my-custom-rule: error
''');

      expect(config.parsingErrors.single, contains('Unknown rule "my-custom-rule"'));
    });

    group('from a file', () {
      late Directory tempDir;

      setUp(() => tempDir = Directory.systemTemp.createTempSync('unknown_rule_names_test.'));
      tearDown(() => tempDir.deleteSync(recursive: true));

      test('with the file and line of each name, including multi-line and flow entries', () async {
        final String configPath = p.join(tempDir.path, 'custom.yaml');
        File(configPath).writeAsStringSync('''
skills_lint:
  rules:
    check-relative-path: error
  directories:
    - path:
        skills
      rules:
        valid-yaml-metadat: error
    - {path: a, rules: {nope-rule: error}}
''');

        final Configuration config = await ConfigParser.loadConfig(path: configPath);
        final String file = canonicalizePath(configPath, baseDirectory: Directory.current.path);

        expect(config.parsingErrors, [
          startsWith('Global rules: Unknown rule "check-relative-path" ($file:3).'),
          startsWith(
            'Directory entry rules for "skills": Unknown rule "valid-yaml-metadat" ($file:8).',
          ),
          startsWith('Directory entry rules for "a": Unknown rule "nope-rule" ($file:9).'),
        ]);
      });

      test('with the file and line when there are only top-level rules', () async {
        final String configPath = p.join(tempDir.path, 'skills_lint.yaml');
        File(configPath).writeAsStringSync('''
skills_lint:
  rules:
    check-relative-path: error
''');

        final Configuration config = await ConfigParser.loadConfig(path: configPath);

        expect(
          config.parsingErrors.single,
          contains('(${canonicalizePath(configPath, baseDirectory: Directory.current.path)}:3)'),
        );
      });
    });
  });

  test('the setup example harness pattern fails on a typo', () {
    final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

    // Mirrors skills/skills-lint-setup/references/validate_skills_example.dart.
    expect(config.parsingErrors, isNot(isEmpty));
  });

  group('validateSkills', () {
    late Directory tempDir;
    late String skillPath;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('unknown_rule_names_api.');
      final Directory skill = await createDummySkill(
        tempDir,
        name: 'my-skill',
        skillContent: '${buildFrontmatter(name: 'my-skill')}Body.\n',
      );
      skillPath = skill.path;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<(bool, String)> run({
      Configuration? config,
      Map<String, RuleConfigPatch> resolvedRuleConfigs = const {},
      List<SkillRule> customRules = const [],
    }) async {
      final err = CapturedOutput();
      final bool passed = await IOOverrides.runZoned(
        () => validateSkills(
          individualSkillPaths: [skillPath],
          config: config,
          resolvedRuleConfigs: resolvedRuleConfigs,
          customRules: customRules,
          quiet: true,
        ),
        stderr: () => err,
      );
      return (passed, err.buffer.toString());
    }

    test('warns about a typo in the configuration and passes', () async {
      final (bool passed, String err) = await run(
        config: ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
'''),
      );

      expect(
        err,
        contains('Configuration warning: Global rules: Unknown rule "check-relative-path".'),
      );
      expect(passed, isTrue);
    });

    test('warns about a typo in resolvedRuleConfigs', () async {
      final (_, String err) = await run(
        resolvedRuleConfigs: {'valid-yaml-metadat': const RuleConfigPatch()},
      );

      expect(
        err,
        contains(
          'Configuration warning: resolvedRuleConfigs: Unknown rule "valid-yaml-metadat". '
          'Did you mean "valid-yaml-metadata"?',
        ),
      );
    });

    test('explains that resolvedRuleConfigs cannot configure a custom rule', () async {
      final (_, String err) = await run(
        resolvedRuleConfigs: {'my-custom-rule': const RuleConfigPatch()},
        customRules: [_NoopRule()],
      );

      expect(
        err,
        contains(
          'resolvedRuleConfigs: "my-custom-rule" is a custom rule, and configuration has no effect',
        ),
      );
    });

    test('accepts built-in names in resolvedRuleConfigs', () async {
      final (_, String err) = await run(
        resolvedRuleConfigs: {'valid-yaml-metadata': const RuleConfigPatch()},
      );

      expect(err, isNot(contains('Configuration warning')));
    });
  });
}

class _NoopRule extends SkillRule {
  @override
  String get name => 'my-custom-rule';

  @override
  AnalysisSeverity get severity => AnalysisSeverity.disabled;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => const [];
}
