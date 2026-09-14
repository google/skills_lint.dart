// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  group('RuleConfig & RuleConfigPatch Merging', () {
    test('RuleConfig initialization defaults', () {
      const config = RuleConfig(severity: AnalysisSeverity.error);
      expect(config.severity, equals(AnalysisSeverity.error));
      expect(config.parameters.params, isEmpty);
      expect(config.severity != AnalysisSeverity.disabled, isTrue);
    });

    test('RuleConfigPatch overrides severity only', () {
      final base = RuleConfig(
        severity: AnalysisSeverity.warning,
        parameters: CustomRuleParameters(const {'exclude': '.*-workspace', 'max': 50}),
      );
      const patch = RuleConfigPatch(severity: AnalysisSeverity.error);

      final RuleConfig merged = patch.applyTo(base);
      expect(merged.severity, equals(AnalysisSeverity.error));
      expect(merged.parameters.params, equals({'exclude': '.*-workspace', 'max': 50}));
    });

    test('RuleConfigPatch overrides parameters only', () {
      final base = RuleConfig(
        severity: AnalysisSeverity.warning,
        parameters: CustomRuleParameters(const {'exclude': '.*-workspace', 'max': 50}),
      );
      final patch = RuleConfigPatch(
        parameters: CustomRuleParameters(const {'max': 100, 'strict': true}),
      );

      final RuleConfig merged = patch.applyTo(base);
      expect(merged.severity, equals(AnalysisSeverity.warning));
      expect(
        merged.parameters.params,
        equals({'exclude': '.*-workspace', 'max': 100, 'strict': true}),
      );
    });

    test('RuleConfigPatch nullifies keys via null value overrides', () {
      final base = RuleConfig(
        severity: AnalysisSeverity.warning,
        parameters: CustomRuleParameters(const {'exclude': '.*-workspace', 'max': 50}),
      );
      final patch = RuleConfigPatch(
        parameters: CustomRuleParameters(const {'exclude': null, 'max': 100}),
      );

      final RuleConfig merged = patch.applyTo(base);
      expect(merged.severity, equals(AnalysisSeverity.warning));
      expect(merged.parameters.params, equals({'max': 100}));
    });
  });

  group('Backwards Compatibility & API Guard Rails', () {
    test(
      'validateSkills throws ArgumentError when passing both resolvedRules and resolvedRuleConfigs',
      () async {
        await withTempDir((tempDir) async {
          final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
          await File(
            '${skillDir.path}/SKILL.md',
          ).writeAsString('${buildFrontmatter(name: 'test-skill')}Body content');

          expect(
            () => validateSkills(
              individualSkillPaths: [skillDir.path],
              // ignore: deprecated_member_use_from_same_package
              resolvedRules: {'valid-yaml-metadata': AnalysisSeverity.warning},
              resolvedRuleConfigs: {
                'valid-yaml-metadata': const RuleConfigPatch(severity: AnalysisSeverity.error),
              },
            ),
            throwsArgumentError,
          );
        });
      },
    );

    test(
      'validateSkills successfully processes deprecated resolvedRules API backwards compatibly',
      () async {
        await withTempDir((tempDir) async {
          final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
          await File('${skillDir.path}/SKILL.md').writeAsString('Invalid YAML No Frontmatter');

          final bool failedByDefault = await validateSkills(individualSkillPaths: [skillDir.path]);
          expect(failedByDefault, isFalse);

          // ignore: deprecated_member_use_from_same_package
          final bool passedWhenDisabled = await validateSkills(
            individualSkillPaths: [skillDir.path],
            // ignore: deprecated_member_use_from_same_package
            resolvedRules: {'valid-yaml-metadata': AnalysisSeverity.disabled},
          );
          expect(passedWhenDisabled, isTrue);
        });
      },
    );
    test('Validator throws ArgumentError when passing both ruleOverrides and ruleConfigs', () {
      expect(
        () => Validator(
          // ignore: deprecated_member_use_from_same_package
          ruleOverrides: {'foo': AnalysisSeverity.warning},
          ruleConfigs: {'foo': const RuleConfig(severity: AnalysisSeverity.error)},
        ),
        throwsArgumentError,
      );
    });

    test('Validator maps deprecated ruleOverrides properly', () {
      // ignore: deprecated_member_use_from_same_package
      final validator = Validator(ruleOverrides: {'foo': AnalysisSeverity.warning});
      // Ensure the mapping happened without error. Validation runs successfully.
      expect(validator, isNotNull);
    });

    test('LintTargetConfig deprecated rules getter maps correctly', () {
      const config = LintTargetConfig(
        path: 'foo',
        ruleConfigs: {'foo': RuleConfigPatch(severity: AnalysisSeverity.warning)},
      );
      // ignore: deprecated_member_use_from_same_package
      expect(config.rules['foo'], equals(AnalysisSeverity.warning));
    });

    test('Configuration deprecated configuredRules getter maps correctly', () {
      const config = Configuration(
        ruleConfigs: {'bar': RuleConfigPatch(severity: AnalysisSeverity.error)},
      );
      // ignore: deprecated_member_use_from_same_package
      expect(config.configuredRules['bar'], equals(AnalysisSeverity.error));
    });

    test('deprecated rules and configuredRules getters omit patches without explicit severity', () {
      const patchWithoutSeverity = RuleConfigPatch();
      const targetConfig = LintTargetConfig(
        path: 'foo',
        ruleConfigs: {'path-does-not-exist': patchWithoutSeverity},
      );
      const topConfig = Configuration(ruleConfigs: {'path-does-not-exist': patchWithoutSeverity});

      // ignore: deprecated_member_use_from_same_package
      expect(targetConfig.rules.containsKey('path-does-not-exist'), isFalse);
      // ignore: deprecated_member_use_from_same_package
      expect(topConfig.configuredRules.containsKey('path-does-not-exist'), isFalse);
    });
  });
  group('RuleConfig & RuleConfigPatch Serialization', () {
    test('RuleConfig methods serialize correctly', () {
      const simpleConfig = RuleConfig(severity: AnalysisSeverity.error);
      expect(simpleConfig.toYaml(), equals('error'));
      expect(simpleConfig.toYamlString(), contains('error'));

      final complexConfig = RuleConfig(
        severity: AnalysisSeverity.warning,
        parameters: CustomRuleParameters(const {'chars': 500, 'strict': true}),
      );
      final Map<String, Object?> expectedMap = {
        'severity': 'warning',
        'chars': 500,
        'strict': true,
      };
      expect(complexConfig.toYaml(), equals(expectedMap));
      expect(complexConfig.toYamlString(), contains('severity: warning'));
      expect(complexConfig.toYamlString(), contains('chars: 500'));
    });

    test('RuleConfigPatch methods serialize correctly', () {
      const severityOnly = RuleConfigPatch(severity: AnalysisSeverity.disabled);
      expect(severityOnly.toYaml(), equals('disabled'));
      expect(severityOnly.toYamlString(), contains('disabled'));

      final paramsOnly = RuleConfigPatch(
        parameters: CustomRuleParameters(const {'exclude': '.*-test'}),
      );
      expect(paramsOnly.toYaml(), equals({'exclude': '.*-test'}));

      const emptyPatch = RuleConfigPatch();
      expect(emptyPatch.toYaml(), equals(<String, Object?>{}));
    });

    test('CustomRuleParameters key named severity does not overwrite rule severity', () {
      final patch = RuleConfigPatch(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {'severity': 'ignored_param'}),
      );
      final Object? yamlObj = patch.toYaml();
      expect(yamlObj, isA<Map<String, Object?>>());
      final Map<String, Object?> map = (yamlObj as Map<String, Object?>?)!;
      expect(map[ConfigParser.severityKey], equals('error'));
    });
  });
}
