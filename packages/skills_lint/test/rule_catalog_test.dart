// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rule_catalog.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/unknown_rule_name_rule.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

const _error = RuleConfigPatch(severity: AnalysisSeverity.error);

void main() {
  group('RuleCatalog.activeRules', () {
    test('creates each enabled built-in check, then the custom rules', () {
      final rule = QuietRule();
      final List<SkillRule> rules = RuleCatalog(customRules: [rule]).activeRules(const {});

      expect(rules.last, same(rule));
      expect(
        rules.map((r) => r.name).toSet(),
        containsAll([
          for (final check in RuleRegistry.allChecks)
            if (check.defaultSeverity != AnalysisSeverity.disabled) check.name,
        ]),
      );
    });

    test('leaves out a disabled built-in check and a disabled custom rule', () {
      final List<SkillRule> rules =
          RuleCatalog(
            customRules: [QuietRule(name: 'off-rule', severity: AnalysisSeverity.disabled)],
          ).activeRules(const {
            'check-relative-paths': RuleConfig(severity: AnalysisSeverity.disabled),
          });

      expect(rules.map((r) => r.name), isNot(contains('check-relative-paths')));
      expect(rules.map((r) => r.name), isNot(contains('off-rule')));
    });

    test('throws on two enabled rules with one name', () {
      final catalog = RuleCatalog(
        customRules: [
          QuietRule(name: 'dup'),
          QuietRule(name: 'dup'),
        ],
      );

      expect(() => catalog.activeRules(const {}), throwsArgumentError);
    });

    test('allows a duplicate name when one of the rules is disabled', () {
      final catalog = RuleCatalog(
        customRules: [
          QuietRule(name: 'dup'),
          QuietRule(name: 'dup', severity: AnalysisSeverity.disabled),
        ],
      );

      expect(catalog.activeRules(const {}).where((r) => r.name == 'dup'), hasLength(1));
    });
  });

  group('RuleCatalog.names', () {
    test('lists built-in checks first, then custom rules', () {
      expect(RuleCatalog(customRules: [QuietRule()]).names, [
        for (final check in RuleRegistry.allChecks) check.name,
        'my-team-rule',
      ]);
    });
  });

  group('RuleCatalog.findUnknownNames', () {
    test('names a misspelled rule, records its YAML line, and suggests the closest rule', () {
      // `check-relative-path` misspells `check-relative-paths` on line 3.
      // The YAML is parsed to check that the parser reports no error for it.
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

      expect(config.parsingErrors, isEmpty);
      final List<UnknownRuleName> findings = const RuleCatalog().findUnknownNames(config);
      expect(findings, hasLength(1));
      expect(findings.single.name, 'check-relative-path');
      expect(findings.single.suggestion, 'check-relative-paths');
      expect(findings.single.line, 3);
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

          final List<UnknownRuleName> findings = const RuleCatalog().findUnknownNames(config);
          expect(findings, hasLength(1));
          expect(findings.single.name, typo);
          expect(findings.single.suggestion, rule);
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

          final List<UnknownRuleName> findings = const RuleCatalog().findUnknownNames(config);
          expect(findings, hasLength(1));
          expect(findings.single.name, typo);
          expect(findings.single.suggestion, isNull);
        });
      }
    });

    test('suggests the closest of several close names', () {
      // `check-relative-pathz` is 1 edit from `check-relative-paths` and 4
      // from the custom rule `check-relative-p`. Both are close enough.
      const config = Configuration(ruleConfigs: {'check-relative-pathz': _error});

      final List<UnknownRuleName> findings = RuleCatalog(
        customRules: [QuietRule(name: 'check-relative-p')],
      ).findUnknownNames(config);
      expect(findings, hasLength(1));
      expect(findings.single.suggestion, 'check-relative-paths');
    });

    test('suggests nothing when a built-in and a custom rule are equally close', () {
      // `check-relative-path` is 1 edit from both `check-relative-paths` and
      // the custom rule `check-relative-patx`. Neither kind is preferred.
      const config = Configuration(ruleConfigs: {'check-relative-path': _error});

      final List<UnknownRuleName> findings = RuleCatalog(
        customRules: [QuietRule(name: 'check-relative-patx')],
      ).findUnknownNames(config);
      expect(findings, hasLength(1));
      expect(findings.single.suggestion, isNull);
    });

    test('names an unknown rule without a suggestion when nothing is close', () {
      const config = Configuration(ruleConfigs: {'no-such-rule-at-all': _error});

      final List<UnknownRuleName> findings = const RuleCatalog().findUnknownNames(config);
      expect(findings, hasLength(1));
      expect(findings.single.name, 'no-such-rule-at-all');
      expect(findings.single.suggestion, isNull);
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
        for (final finding in const RuleCatalog().findUnknownNames(config))
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
      expect(RuleCatalog(customRules: [QuietRule()]).findUnknownNames(config), isEmpty);
    });

    test('suggests a custom rule for a misspelling of it', () {
      // `my-team-rul` misspells the custom rule `my-team-rule`.
      const config = Configuration(ruleConfigs: {'my-team-rul': _error});

      final List<UnknownRuleName> findings = RuleCatalog(
        customRules: [QuietRule()],
      ).findUnknownNames(config);
      expect(findings, hasLength(1));
      expect(findings.single.name, 'my-team-rul');
      expect(findings.single.suggestion, 'my-team-rule');
    });

    test('does not flag a name in allowed', () {
      const config = Configuration(ruleConfigs: {'rule-from-a-newer-version': _error});

      expect(
        const RuleCatalog().findUnknownNames(config, allowed: ['rule-from-a-newer-version']),
        isEmpty,
      );
    });

    test('does not flag any built-in rule', () {
      final config = Configuration(
        ruleConfigs: {for (final check in RuleRegistry.allChecks) check.name: _error},
      );

      expect(const RuleCatalog().findUnknownNames(config), isEmpty);
    });
  });

  group('UnknownRuleNameRule.validate', () {
    test('attaches the configuration file and YAML line to the ValidationError', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    unknown-rule-name: error
    check-relative-path: error
''', configSource: const ConfigSource.file('/repo/skills_lint.yaml'));

      final List<ValidationError> errors = UnknownRuleNameRule(
        severity: AnalysisSeverity.error,
      ).validate(config);

      expect(errors, hasLength(1));
      expect(errors.single.ruleId, UnknownRuleNameRule.ruleName);
      expect(errors.single.file, endsWith('skills_lint.yaml'));
      expect(errors.single.region?.startLine, 4);
      expect(
        errors.single.message,
        allOf(contains('check-relative-path'), contains('check-relative-paths')),
      );
    });
  });
}
