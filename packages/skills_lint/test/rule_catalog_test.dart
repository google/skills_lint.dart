// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rule_catalog.dart';
import 'package:skills_lint/src/rule_registry.dart';
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
    test('names a misspelled rule, which the parser accepts, and suggests the closest rule', () {
      // `check-relative-path` misspells `check-relative-paths`. The YAML is
      // parsed to check that the parser reports no error for it.
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-path: error
''');

      expect(config.parsingErrors, isEmpty);
      expect(_messages(config, const []), [
        'Global rules: Unknown rule "check-relative-path". Did you mean "check-relative-paths"?',
      ]);
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

          expect(_messages(config, const []), [
            'Global rules: Unknown rule "$typo". Did you mean "$rule"?',
          ]);
        });
      }
    });

    group('names a rule class name without a suggestion:', () {
      // A rule's Dart class name can differ from its rule name.
      // `description-length` appears in a comment in api_defaults_test.dart
      // for `description-too-long` (DescriptionLengthRule).
      for (final typo in ['description-length', 'name-format']) {
        test(typo, () {
          final config = Configuration(ruleConfigs: {typo: _error});

          expect(_messages(config, const []), ['Global rules: Unknown rule "$typo".']);
        });
      }
    });

    test('names an unknown rule without a suggestion when nothing is close', () {
      const config = Configuration(ruleConfigs: {'no-such-rule-at-all': _error});

      expect(_messages(config, const []), ['Global rules: Unknown rule "no-such-rule-at-all".']);
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

      expect(_messages(config, const []), [
        'Directory entry rules for "skills": Unknown rule "check-relative-path". Did you mean "check-relative-paths"?',
        'Individual skill entry rules for "one/skill": Unknown rule "bogus-rule-name-here".',
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
      expect(_messages(config, [QuietRule()]), isEmpty);
    });

    test('suggests a custom rule for a misspelling of it', () {
      // `my-team-rul` misspells the custom rule `my-team-rule`.
      const config = Configuration(ruleConfigs: {'my-team-rul': _error});

      expect(_messages(config, [QuietRule()]), [
        'Global rules: Unknown rule "my-team-rul". Did you mean "my-team-rule"?',
      ]);
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

      expect(_messages(config, const []), isEmpty);
    });
  });
}

/// The messages of [RuleCatalog.findUnknownNames] for [config] and [customRules].
List<String> _messages(Configuration config, List<SkillRule> customRules) => [
  for (final UnknownRuleName unknown in RuleCatalog(
    customRules: customRules,
  ).findUnknownNames(config))
    unknown.message,
];
