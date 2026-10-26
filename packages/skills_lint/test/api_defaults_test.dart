// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rules/description_length_rule.dart';
import 'package:skills_lint/src/rules/trailing_whitespace_rule.dart';
import 'package:skills_lint/src/rules/valid_yaml_metadata_rule.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('validateSkills applies default rules when not specified', () async {
    await withTempDir((tempDir) async {
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: 'test-skill',
        skillContent: 'Invalid YAML No Frontmatter',
      );

      // Call validateSkills with empty overrides.
      // It should apply default rules, including valid-yaml-metadata.
      final bool isValid = await validateSkills(individualSkillPaths: [skillDir.path]);

      expect(isValid, isFalse, reason: 'Should fail due to default rule valid-yaml-metadata.');
    });
  });

  test('Validator skips disabled rules', () async {
    await withTempDir((tempDir) async {
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: 'test-skill',
        skillContent: 'Invalid YAML No Frontmatter',
      );

      // Create validator with the rule disabled.
      final validator = Validator(
        ruleConfigs: {
          ValidYamlMetadataRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      final bool hasYamlError = result.validationErrors.any(
        (e) => e.ruleId == ValidYamlMetadataRule.ruleName,
      );
      expect(
        hasYamlError,
        isFalse,
        reason: 'Should not have valid-yaml-metadata error when disabled.',
      );
    });
  });

  test('loadConfig resolves tilde in custom config path', () async {
    final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    expect(home, isNotNull, reason: 'HOME or USERPROFILE environment variable must be set.');

    final tempFile = File(p.join(home!, 'skills_lint_temp_test.yaml'));
    await tempFile.writeAsString('''
skills_lint:
  rules:
    check-relative-paths: error
''');

    try {
      // Under the current code, this will fail because loadConfig does not do tilde expansion.
      final Configuration config = await ConfigParser.loadConfig(
        path: '~/skills_lint_temp_test.yaml',
      );
      expect(config.ruleConfigs, contains('check-relative-paths'));
    } finally {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    }
  });

  test('Path resolution avoids collision with prefix-sharing directories', () async {
    await withTempDir((tempDir) async {
      // We create two directories: 'skills-tests/test-skill' (the one being evaluated)
      // and 'skills' (the one defined in config)
      final configDir = Directory(p.join(tempDir.path, 'skills'));
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: 'skills-tests/test-skill',
        skillContent: '''
---
name: test-skill
description: A test skill
---
Line with space 
''', // Trailing space
      );

      // Create a Configuration with rules enabled specifically for 'skills'
      final config = Configuration(
        directoryConfigs: [
          LintTargetConfig(
            path: configDir.path,
            ruleConfigs: const {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
      );

      // Call validateSkills. Under unsafe prefix-matching, 'skills-tests'
      // starts with 'skills' (prefix collision) and enables trailing whitespace checks as error.
      // It should pass because 'skills-tests' is NOT the same directory as 'skills'.
      final bool isValid = await validateSkills(
        individualSkillPaths: [skillDir.path],
        config: config,
      );

      expect(
        isValid,
        isTrue,
        reason: 'Should pass because skills-tests does not match configuration for skills.',
      );
    });
  });

  test('loadConfig captures YAML parsing errors in Configuration.parsingErrors', () async {
    await withTempDir((tempDir) async {
      final configFile = File(p.join(tempDir.path, 'skills_lint.yaml'));
      await configFile.writeAsString('''
skills_lint:
  rules:
    check-trailing-whitespace: [error, warning
'''); // unclosed bracket YAML syntax error

      final Configuration config = await ConfigParser.loadConfig(path: configFile.path);

      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Failed to parse'));
    });
  });

  group('validateSkills with configuration errors', () {
    /// Runs [validate] on the valid example skill with the configuration
    /// parsed from [yaml], and returns its result and what it wrote to
    /// standard error.
    Future<(bool, String)> run(
      String yaml, {
      Future<bool> Function({Configuration? config}) validate = _validateSkills,
    }) async {
      final Configuration config = ConfigParser.parse(yaml);
      final err = CapturedOutput();
      final bool passed = await IOOverrides.runZoned(
        () => validate(config: config),
        stderr: () => err,
      );
      return (passed, err.buffer.toString());
    }

    test('prints an unknown rule parameter as a warning and passes', () async {
      final (bool passed, String err) = await run(_typoConfig);

      expect(
        err,
        contains(
          'Configuration warning: Global rules: Unrecognized parameter "within-skil" '
          'for rule "check-relative-paths".',
        ),
      );
      expect(passed, isTrue);
    });

    test('prints every configuration error', () async {
      const yaml = '''
skills_lint:
  bogus: 1
  rules:
    check-relative-paths:
      within-skill: maybe
''';
      final List<String> errors = ConfigParser.parse(yaml).parsingErrors;
      expect(errors, hasLength(2));

      final (_, String err) = await run(yaml);

      for (final error in errors) {
        expect(err, contains('Configuration warning: $error'));
      }
    });

    test('prints no configuration warning for a valid configuration', () async {
      final (bool passed, String err) = await run('''
skills_lint:
  rules:
    check-relative-paths:
      severity: error
      within-skill: true
''');

      expect(err, isNot(contains('Configuration warning')));
      expect(passed, isTrue);
    });

    test('validateSkillsInternal leaves configuration errors to its caller', () async {
      // The CLI reports configuration errors itself before it calls
      // validateSkillsInternal, so they must not print twice.
      final (_, String err) = await run(
        _typoConfig,
        validate: ({Configuration? config}) => validateSkillsInternal(
          individualSkillPaths: [_validSkillPath],
          config: config,
          quiet: true,
        ),
      );

      expect(err, isNot(contains('Configuration warning')));
    });
  });

  test('Nested Directory Rule Inheritance merging and precedence override', () async {
    await withTempDir((tempDir) {
      // parent path: 'skills' (enables check-trailing-whitespace: error, description-length: warning)
      // child path: 'skills/nested' (enables description-length: error, check-trailing-whitespace: disabled)
      final config = Configuration(
        directoryConfigs: [
          LintTargetConfig(
            path: p.join(tempDir.path, 'skills'),
            ruleConfigs: const {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              DescriptionLengthRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
            },
          ),
          LintTargetConfig(
            path: p.join(tempDir.path, 'skills/nested'),
            ruleConfigs: const {
              DescriptionLengthRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
            },
          ),
        ],
      );

      final session = ValidationSession(
        config: config,
        ignoreFileOverride: null,
        customRules: [],
        printWarnings: true,
        fastFail: false,
        quiet: true,
        generateBaseline: false,
        fix: false,
        fixApply: false,
      );

      // Parent path should have parent rules applied
      final Map<String, RuleConfig> parentRules = session.resolveRuleConfigsForPath(
        p.join(tempDir.path, 'skills/some-skill'),
      );
      expect(
        parentRules[TrailingWhitespaceRule.ruleName]?.severity,
        equals(AnalysisSeverity.error),
      );
      expect(
        parentRules[DescriptionLengthRule.ruleName]?.severity,
        equals(AnalysisSeverity.warning),
      );

      // Child path should merge and override parent rules
      final Map<String, RuleConfig> childRules = session.resolveRuleConfigsForPath(
        p.join(tempDir.path, 'skills/nested/nested-skill'),
      );
      expect(
        childRules[TrailingWhitespaceRule.ruleName]?.severity,
        equals(AnalysisSeverity.disabled),
      ); // child override
      expect(
        childRules[DescriptionLengthRule.ruleName]?.severity,
        equals(AnalysisSeverity.error),
      ); // child override
    });
  });

  test('Nested Directory Ignore File Inheritance', () async {
    await withTempDir((tempDir) {
      // parent path: 'skills' (defines ignoreFile)
      // child path: 'skills/nested' (does not define ignoreFile, should inherit)
      final config = Configuration(
        directoryConfigs: [
          LintTargetConfig(path: p.join(tempDir.path, 'skills'), ignoreFile: 'parent_ignores.json'),
          LintTargetConfig(path: p.join(tempDir.path, 'skills/nested')),
        ],
      );

      final session = ValidationSession(
        config: config,
        ignoreFileOverride: null,
        customRules: [],
        printWarnings: true,
        fastFail: false,
        quiet: true,
        generateBaseline: false,
        fix: false,
        fixApply: false,
      );

      // A configuration built in memory holds a relative ignore file, so the
      // session anchors it to the working directory.
      final String anchoredIgnoreFile = p.normalize(p.absolute('parent_ignores.json'));

      // Parent ignore file should match
      expect(
        session.resolveIgnoreFile(p.join(tempDir.path, 'skills/some-skill')),
        equals(anchoredIgnoreFile),
      );

      // Child should inherit parent ignore file
      expect(
        session.resolveIgnoreFile(p.join(tempDir.path, 'skills/nested/nested-skill')),
        equals(anchoredIgnoreFile),
      );
    });
  });

  test('Absolute vs. Relative Path Resolution matching', () {
    // Config defines path as relative 'skills'
    const config = Configuration(
      directoryConfigs: [
        LintTargetConfig(
          path: 'skills',
          ruleConfigs: {
            TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          },
        ),
      ],
    );

    final session = ValidationSession(
      config: config,
      ignoreFileOverride: null,
      customRules: [],
      printWarnings: true,
      fastFail: false,
      quiet: true,
      generateBaseline: false,
      fix: false,
      fixApply: false,
    );

    // 1. Evaluate relative input: 'skills/my-skill'
    final Map<String, RuleConfig> relativeRules = session.resolveRuleConfigsForPath(
      'skills/my-skill',
    );
    expect(
      relativeRules[TrailingWhitespaceRule.ruleName]?.severity,
      equals(AnalysisSeverity.error),
    );

    // 2. Evaluate absolute input
    final String absoluteInput = p.absolute('skills/my-skill');
    final Map<String, RuleConfig> absoluteRules = session.resolveRuleConfigsForPath(absoluteInput);
    expect(
      absoluteRules[TrailingWhitespaceRule.ruleName]?.severity,
      equals(AnalysisSeverity.error),
    );
  });
}

const _typoConfig = '''
skills_lint:
  rules:
    check-relative-paths:
      severity: error
      within-skil: true
''';

final String _validSkillPath = p.normalize(p.absolute(p.join('example', 'skills', 'valid')));

/// Calls [validateSkills] on the valid example skill.
Future<bool> _validateSkills({Configuration? config}) =>
    validateSkills(individualSkillPaths: [_validSkillPath], config: config, quiet: true);
