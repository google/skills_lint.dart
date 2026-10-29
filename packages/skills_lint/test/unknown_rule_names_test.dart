// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/unknown_rule_names.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

const _known = ['check-relative-paths', 'check-trailing-whitespace', 'valid-yaml-metadata'];

void main() {
  group('unknownRuleNameErrors', () {
    test('reports a top-level typo with a suggestion', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

      expect(unknownRuleNameErrors(config, knownNames: _known), [
        'Unknown rule "check-relative-path" in rules. Did you mean "check-relative-paths"?',
      ]);
    });

    test('reports no suggestion when nothing is close', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    zzz: error
''');

      expect(unknownRuleNameErrors(config, knownNames: _known), ['Unknown rule "zzz" in rules.']);
    });

    test('lists every equally close name', () {
      const config = Configuration(
        ruleConfigs: {'rule-c': RuleConfigPatch(severity: AnalysisSeverity.error)},
      );

      expect(unknownRuleNameErrors(config, knownNames: ['rule-a', 'rule-b']), [
        'Unknown rule "rule-c" in rules. Did you mean "rule-a" or "rule-b"?',
      ]);
    });

    test('names the target entry a typo is in', () {
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

      expect(unknownRuleNameErrors(config, knownNames: _known), [
        'Unknown rule "valid-yaml-metadat" in directories[".agents/skills"].rules. Did you mean "valid-yaml-metadata"?',
        'Unknown rule "check-trailing-whitespac" in individual_skills["one/skill"].rules. Did you mean "check-trailing-whitespace"?',
      ]);
    });

    test('checks override keys', () {
      expect(
        unknownRuleNameErrors(
          const Configuration(),
          knownNames: _known,
          overrides: {'valid-yaml-metadat': const RuleConfigPatch()},
        ),
        [
          'Unknown rule "valid-yaml-metadat" in resolvedRuleConfigs. Did you mean "valid-yaml-metadata"?',
        ],
      );
    });

    test('accepts every known name', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    my-custom-rule: error
    check-relative-paths: warning
''');

      expect(unknownRuleNameErrors(config, knownNames: [..._known, 'my-custom-rule']), isEmpty);
    });

    group('with a configuration file', () {
      late Directory tempDir;
      late String configPath;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('unknown_rule_names_test.');
        configPath = p.join(tempDir.path, 'custom.yaml');
        File(configPath).writeAsStringSync('''
skills_lint:
  rules:
    check-relative-path: error
  directories:
    - path: a
    - path: b
      rules:
        valid-yaml-metadat: error
''');
      });

      tearDown(() => tempDir.deleteSync(recursive: true));

      test('shows the file and line of each typo', () async {
        final Configuration config = await ConfigParser.loadConfig(path: configPath);

        expect(unknownRuleNameErrors(config, knownNames: _known, configFile: configPath), [
          'Unknown rule "check-relative-path" in rules ($configPath:3). Did you mean "check-relative-paths"?',
          'Unknown rule "valid-yaml-metadat" in directories["b"].rules ($configPath:8). Did you mean "valid-yaml-metadata"?',
        ]);
      });

      test('finds the file from the parsed targets when none is given', () async {
        final Configuration config = await ConfigParser.loadConfig(path: configPath);

        expect(
          unknownRuleNameErrors(config, knownNames: _known).first,
          contains('($configPath:3)'),
        );
      });
    });
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

    test('warns about a typo in an in-code configuration and passes', () async {
      final (bool passed, String err) = await run(
        config: const Configuration(
          ruleConfigs: {'check-relative-path': RuleConfigPatch(severity: AnalysisSeverity.error)},
        ),
      );

      expect(
        err,
        contains(
          'Configuration warning: Unknown rule "check-relative-path" in rules. '
          'Did you mean "check-relative-paths"?',
        ),
      );
      expect(passed, isTrue);
    });

    test('shows file and line for a loaded configuration', () async {
      final String configPath = p.join(tempDir.path, 'skills_lint.yaml');
      File(configPath).writeAsStringSync('''
skills_lint:
  individual_skills:
    - path: my-skill
      rules:
        check-relative-path: error
''');
      final Configuration config = await ConfigParser.loadConfig(path: configPath);

      final (_, String err) = await run(config: config);

      expect(
        err,
        contains(
          'Configuration warning: Unknown rule "check-relative-path" in '
          'individual_skills["my-skill"].rules ($configPath:5).',
        ),
      );
    });

    test('warns about a typo in resolvedRuleConfigs', () async {
      final (_, String err) = await run(
        resolvedRuleConfigs: {'valid-yaml-metadat': const RuleConfigPatch()},
      );

      expect(
        err,
        contains(
          'Configuration warning: Unknown rule "valid-yaml-metadat" in resolvedRuleConfigs.',
        ),
      );
    });

    test('knows the names of custom rules', () async {
      final (_, String err) = await run(
        config: const Configuration(
          ruleConfigs: {'my-custom-rule': RuleConfigPatch(severity: AnalysisSeverity.error)},
        ),
        customRules: [_NoopRule()],
      );

      expect(err, isNot(contains('Unknown rule')));
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
