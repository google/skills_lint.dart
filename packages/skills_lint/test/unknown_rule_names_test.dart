// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/unknown_rule_name_rule.dart';
import 'package:skills_lint/src/unknown_rule_names.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

const _error = RuleConfigPatch(severity: AnalysisSeverity.error);

void main() {
  group('findUnknownRuleNames', () {
    test('names a misspelled rule, records where it is, and suggests the closest rule', () {
      // `check-relative-path` misspells `check-relative-paths`.
      // The YAML is parsed to check that the parser reports no error for it.
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

      expect(config.parsingErrors, isEmpty);
      final List<UnknownRuleName> findings = findUnknownRuleNames(config, const []);
      expect(findings, hasLength(1));
      expect(findings.single.name, 'check-relative-path');
      expect(findings.single.suggestions, ['check-relative-paths']);
      expect(findings.single.key, (
        section: 'rules',
        entryIndex: null,
        ruleName: 'check-relative-path',
      ));
      expect(
        UnknownRuleNameRule.formatMessage(findings.single),
        allOf(
          contains('Global rules'),
          contains('check-relative-path'),
          contains('check-relative-paths'),
        ),
      );
    });

    group('suggests the rule for a common mistake:', () {
      const cases = {
        'checkrelative-paths': 'check-relative-paths',
        'Check-Relative-Paths': 'check-relative-paths',
        'check_absolute_paths': 'check-absolute-paths',
        'disallowed-feild': 'disallowed-field',
        'valid-yaml-metdata': 'valid-yaml-metadata',
        'published-skill-names': 'published-skill-name',
        'trailing-whitespace': 'check-trailing-whitespace',
      };
      for (final MapEntry(key: typo, value: rule) in cases.entries) {
        test(typo, () {
          final config = Configuration(ruleConfigs: {typo: _error});

          final List<UnknownRuleName> findings = findUnknownRuleNames(config, const []);
          expect(findings, hasLength(1));
          expect(findings.single.name, typo);
          expect(findings.single.suggestions, [rule]);
          expect(
            UnknownRuleNameRule.formatMessage(findings.single),
            allOf(contains(typo), contains(rule)),
          );
        });
      }
    });

    group('gives no suggestion when a mistake is too far from any rule name:', () {
      // Writing a rule's Dart class stem (such as `description-length` for
      // `DescriptionLengthRule` instead of `description-too-long`, or
      // `name-format` for `NameFormatRule` instead of `invalid-skill-name`)
      // exceeds the edit-distance threshold, so suggestion is null.
      for (final typo in ['description-length', 'name-format']) {
        test(typo, () {
          final config = Configuration(ruleConfigs: {typo: _error});

          final List<UnknownRuleName> findings = findUnknownRuleNames(config, const []);
          expect(findings, hasLength(1));
          expect(findings.single.name, typo);
          expect(findings.single.suggestions, isEmpty);
        });
      }
    });

    test('suggests the closest of several close names', () {
      // `check-relative-pathz` is 1 edit from `check-relative-paths` and 4
      // from the custom rule `check-relative-p`. Both are close enough.
      const config = Configuration(ruleConfigs: {'check-relative-pathz': _error});

      final List<UnknownRuleName> findings = findUnknownRuleNames(config, [
        QuietRule(name: 'check-relative-p'),
      ]);
      expect(findings, hasLength(1));
      expect(findings.single.suggestions, ['check-relative-paths']);
    });

    test('suggests both when a built-in and a custom rule are equally close', () {
      // `check-relative-path` is 1 edit from both `check-relative-paths` and
      // the custom rule `check-relative-patx`. Neither kind is preferred.
      const config = Configuration(ruleConfigs: {'check-relative-path': _error});

      final List<UnknownRuleName> findings = findUnknownRuleNames(config, [
        QuietRule(name: 'check-relative-patx'),
      ]);
      expect(findings, hasLength(1));
      expect(findings.single.suggestions, ['check-relative-paths', 'check-relative-patx']);
    });

    test('names an unknown rule without a suggestion when nothing is close', () {
      const config = Configuration(ruleConfigs: {'no-such-rule-at-all': _error});

      final List<UnknownRuleName> findings = findUnknownRuleNames(config, const []);
      expect(findings, hasLength(1));
      expect(findings.single.name, 'no-such-rule-at-all');
      expect(findings.single.suggestions, isEmpty);
    });

    test('checks the rules of directory and individual skill entries', () {
      // `check-relative-path` misspells `check-relative-paths`.
      const config = Configuration(
        directoryConfigs: [
          LintTargetConfig(path: 'skills', ruleConfigs: {'check-relative-path': _error}),
        ],
        individualSkillConfigs: [
          LintTargetConfig(path: 'one/skill', ruleConfigs: {'bogus-rule-name-here': _error}),
        ],
      );

      final List<String> messages = [
        for (final finding in findUnknownRuleNames(config, const []))
          UnknownRuleNameRule.formatMessage(finding),
      ];
      expect(messages, [
        allOf(
          contains('skills'),
          contains('check-relative-path'),
          contains('check-relative-paths'),
        ),
        allOf(contains('one/skill'), contains('bogus-rule-name-here')),
      ]);
    });

    test('does not flag a custom rule, and the parser accepts its parameters', () {
      // Parsed so that the parser's handling of an unknown parameter is
      // checked too.
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    my-team-rule:
      severity: error
      threshold: 3
''');

      expect(config.parsingErrors, isEmpty);
      expect(findUnknownRuleNames(config, [QuietRule()]), isEmpty);
    });

    test('suggests a custom rule for a misspelling of it', () {
      // `my-team-rul` misspells the custom rule `my-team-rule`.
      const config = Configuration(ruleConfigs: {'my-team-rul': _error});

      final List<UnknownRuleName> findings = findUnknownRuleNames(config, [QuietRule()]);
      expect(findings, hasLength(1));
      expect(findings.single.name, 'my-team-rul');
      expect(findings.single.suggestions, ['my-team-rule']);
    });

    test('does not flag a name in allowed', () {
      const config = Configuration(ruleConfigs: {'rule-from-a-newer-version': _error});

      expect(
        findUnknownRuleNames(config, const [], allowed: ['rule-from-a-newer-version']),
        isEmpty,
      );
    });

    test('does not flag any built-in rule', () {
      final config = Configuration(
        ruleConfigs: {for (final check in RuleRegistry.allChecks) check.name: _error},
      );

      expect(findUnknownRuleNames(config, const []), isEmpty);
    });
  });

  group('UnknownRuleNameRule.validate', () {
    late Directory tempDir;
    late String configFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('unknown_rule_name_test.');
      configFile = p.join(tempDir.path, 'skills_lint.yaml');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    List<ValidationError> validateFile(String yaml, {bool passFile = true}) {
      File(configFile).writeAsStringSync(yaml);
      final Configuration config = ConfigParser.parse(
        yaml,
        configSource: ConfigSource.file(configFile),
      );
      return UnknownRuleNameRule(
        severity: AnalysisSeverity.error,
      ).validate(config, configFile: passFile ? configFile : null);
    }

    test('points a top-level rule name at its line in the configuration file', () {
      final List<ValidationError> errors = validateFile('''
skills_lint:
  rules:
    unknown-rule-name: error
    check-relative-path: error
''');

      expect(errors, hasLength(1));
      expect(errors.single.ruleId, UnknownRuleNameRule.ruleName);
      expect(errors.single.file, configFile);
      expect(errors.single.region?.startLine, 4);
      expect(
        errors.single.message,
        allOf(contains('check-relative-path'), contains('check-relative-paths')),
      );
    });

    test('has no line for a configuration parsed without a file', () {
      final List<ValidationError> errors = validateFile('''
skills_lint:
  rules:
    check-relative-path: error
''', passFile: false);

      expect(errors, hasLength(1));
      expect(errors.single.file, 'skills_lint.yaml');
      expect(errors.single.region, isNull);
    });

    test('tells apart two directory entries with the same path', () {
      final List<ValidationError> errors = validateFile('''
skills_lint:
  directories:
    - path: skills
      rules:
        check-relative-paths: error
    - path: skills
      rules:
        check-relative-path: error
''');

      expect(errors, hasLength(1));
      expect(errors.single.region?.startLine, 8);
    });

    test('has no line when a dropped entry shifts the entry index', () {
      // The first entry has no path, so the parser drops it. The typo is in
      // the second YAML entry, which is the first parsed entry. Index 0 in
      // the YAML has no such rule, so no line is better than a wrong one.
      final List<ValidationError> errors = validateFile('''
skills_lint:
  directories:
    - rules:
        check-relative-paths: error
    - path: skills
      rules:
        check-relative-path: error
''');

      expect(errors, hasLength(1));
      expect(errors.single.region, isNull);
    });
  });
}
