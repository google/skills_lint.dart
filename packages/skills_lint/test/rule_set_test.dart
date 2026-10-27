// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart' hide RuleDefinition, RuleSet;
import 'package:skills_lint/src/config_serializer.dart';
import 'package:skills_lint/src/models/sarif/sarif.dart';
import 'package:skills_lint/src/rule_set.dart';
import 'package:skills_lint/src/unknown_rule_names.dart';
import 'package:test/test.dart';

const String _ruleName = 'team-max-lines';
const String _maxParameter = 'max';

/// A custom rule that records the severity and parameters it was built with.
class _TeamRule extends SkillRule {
  _TeamRule(this.severity, this.max);

  @override
  final String name = _ruleName;

  @override
  final AnalysisSeverity severity;

  final int? max;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => const [];
}

/// A custom rule passed as an object, whose severity the caller fixes.
class _FixedRule extends SkillRule {
  _FixedRule(this.name, this.severity);

  @override
  final String name;

  @override
  final AnalysisSeverity severity;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => const [];
}

final RuleDefinition _teamDefinition = RuleDefinition(
  check: CheckType(
    name: _ruleName,
    defaultSeverity: AnalysisSeverity.warning,
    help: 'Check that SKILL.md is short.',
    parameterSchema: const {_maxParameter: RuleParameterType.integer},
    parameterConstraints: {
      _maxParameter: ParameterConstraint(
        description: 'a positive integer',
        accepts: (Object value) => value is int && value > 0,
      ),
    },
  ),
  create: (severity, parameters) => _TeamRule(severity, parameters?.getInt(_maxParameter)),
);

_TeamRule? _builtTeamRule(RuleSet ruleSet, Map<String, RuleConfig> ruleConfigs) =>
    ruleSet.buildRules(ruleConfigs).whereType<_TeamRule>().firstOrNull;

void main() {
  group('RuleSet', () {
    test('lists built-in rules first, then custom definitions, then custom rules', () {
      final ruleSet = RuleSet(
        customDefinitions: [_teamDefinition],
        customRules: [_FixedRule('fixed-rule', AnalysisSeverity.error)],
      );

      final List<String> names = ruleSet.names.toList();

      expect(names.first, 'path-does-not-exist');
      expect(names.sublist(names.length - 2), [_ruleName, 'fixed-rule']);
    });

    test('builds a custom definition at its default severity when unconfigured', () {
      final _TeamRule? rule = _builtTeamRule(RuleSet(customDefinitions: [_teamDefinition]), {});

      expect(rule?.severity, AnalysisSeverity.warning);
      expect(rule?.max, isNull);
    });

    test('builds a custom definition with its configured severity and parameters', () {
      final _TeamRule? rule = _builtTeamRule(RuleSet(customDefinitions: [_teamDefinition]), {
        _ruleName: RuleConfig(
          severity: AnalysisSeverity.error,
          parameters: CustomRuleParameters(const {_maxParameter: 40}),
        ),
      });

      expect(rule?.severity, AnalysisSeverity.error);
      expect(rule?.max, 40);
    });

    test('leaves out a custom definition that the configuration disables', () {
      final _TeamRule? rule = _builtTeamRule(RuleSet(customDefinitions: [_teamDefinition]), {
        _ruleName: const RuleConfig(severity: AnalysisSeverity.disabled),
      });

      expect(rule, isNull);
    });

    test('rejects a configured parameter that breaks its constraint', () {
      final ruleSet = RuleSet(customDefinitions: [_teamDefinition]);

      expect(
        () => ruleSet.buildRules({
          _ruleName: RuleConfig(
            severity: AnalysisSeverity.error,
            parameters: CustomRuleParameters(const {_maxParameter: 0}),
          ),
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('Expected a positive integer, got "0"'),
          ),
        ),
      );
    });

    test('keeps the severity of a rule passed as customRules, whatever the configuration says', () {
      final fixed = _FixedRule('fixed-rule', AnalysisSeverity.warning);
      final ruleSet = RuleSet(customRules: [fixed]);

      final List<SkillRule> rules = ruleSet.buildRules({
        'fixed-rule': const RuleConfig(severity: AnalysisSeverity.disabled),
      });

      expect(rules, contains(same(fixed)));
    });

    test('throws when two enabled rules share a name', () {
      final ruleSet = RuleSet(
        customDefinitions: [_teamDefinition],
        customRules: [_FixedRule(_ruleName, AnalysisSeverity.error)],
      );

      expect(
        () => ruleSet.buildRules({}),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            'Duplicate rule name detected: $_ruleName',
          ),
        ),
      );
    });
  });

  group('custom definitions in a configuration', () {
    test('round-trip through YAML with their severity and parameters', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    $_ruleName:
      severity: error
      $_maxParameter: 40
''');

      final Configuration reparsed = ConfigParser.parse(
        ConfigSerializer.toYamlString(config.toYaml()),
      );

      expect(reparsed.parsingErrors, isEmpty);
      expect(reparsed.ruleConfigs[_ruleName]?.severity, AnalysisSeverity.error);
      expect(reparsed.ruleConfigs[_ruleName]?.parameters?.getInt(_maxParameter), 40);
    });

    test('are not reported as unknown rule names', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    $_ruleName: error
''');

      expect(
        unknownRuleNameWarnings(config, RuleSet(customDefinitions: [_teamDefinition])),
        isEmpty,
      );
    });

    test('keep their default severity when the configuration sets only parameters', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    $_ruleName:
      $_maxParameter: 40
''');
      final session = ValidationSession(
        config: config,
        ignoreFileOverride: null,
        customRules: const [],
        customRuleDefinitions: [_teamDefinition],
        printWarnings: false,
        fastFail: false,
        quiet: true,
        generateBaseline: false,
        fix: false,
        fixApply: false,
      );

      final RuleConfig? resolved = session.resolveRuleConfigsForPath('skills/a')[_ruleName];

      expect(resolved?.severity, AnalysisSeverity.warning);
      expect(resolved?.parameters.getInt(_maxParameter), 40);
    });

    test('appear in SARIF output as custom rules with their help text', () {
      final SarifLog sarif = SarifSerializer.toSarifLog(
        [],
        ruleSet: RuleSet(customDefinitions: [_teamDefinition]),
      );

      final SarifRule rule = sarif.runs.single.tool.driver.rules.singleWhere(
        (SarifRule r) => r.id == _ruleName,
      );
      expect(rule.shortDescription.text, 'Check that SKILL.md is short.');
      expect(rule.defaultConfiguration?.level, 'warning');
      expect(rule.properties?[SarifRule.keyTags], ['lint', 'quality', 'custom-rule']);
    });
  });
}
