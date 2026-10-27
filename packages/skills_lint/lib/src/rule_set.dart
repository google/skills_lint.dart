// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/custom_rule_parameters.dart';
import 'models/rule_config.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';

/// Builds a [SkillRule] from the severity and parameters that the
/// configuration gives it.
typedef SkillRuleFactory =
    SkillRule Function(AnalysisSeverity severity, CustomRuleParameters parameters);

/// Describes a custom rule that a configuration can name: its [check] (name,
/// default severity, help text and parameter schema) and how to [create] it.
///
/// `skills_lint.yaml` refers to a rule by name and gives its severity and
/// parameters, so a configuration that turns on a custom rule round-trips
/// through YAML like one that turns on a built-in rule. The Dart code that
/// runs the rule stays here.
///
/// ```dart
/// final definition = RuleDefinition(
///   check: const CheckType(
///     name: 'no-todo',
///     defaultSeverity: AnalysisSeverity.warning,
///     help: 'Check for TODO in SKILL.md.',
///   ),
///   create: (severity, _) => NoTodoRule(severity: severity),
/// );
/// ```
final class RuleDefinition {
  /// Creates a definition for a rule that the configuration can enable,
  /// disable and give parameters to.
  const RuleDefinition({required this.check, required this.create});

  /// The rule's name, default severity, help text and parameter schema.
  final CheckType check;

  /// Builds the rule from its configured severity and parameters.
  ///
  /// It is not called for a rule that the configuration disables.
  final SkillRuleFactory create;

  /// The rule's name, as written in configuration.
  String get name => check.name;
}

/// The rules one validation run knows about: every built-in rule, then the
/// caller's [RuleDefinition]s, then the caller's [SkillRule]s.
///
/// Building, reporting and checking configured rule names all read this one
/// object.
final class RuleSet {
  /// Creates a set of the built-in rules plus [customDefinitions] and
  /// [customRules].
  ///
  /// Throws an [ArgumentError] when a name in [customDefinitions] is already
  /// taken by a built-in rule or another definition.
  RuleSet({
    List<RuleDefinition> customDefinitions = const [],
    List<SkillRule> customRules = const [],
  }) : _customDefinitions = List.unmodifiable(customDefinitions),
       _customRules = List.unmodifiable(customRules) {
    final Set<String> names = {for (final CheckType check in RuleRegistry.allChecks) check.name};
    for (final RuleDefinition definition in _customDefinitions) {
      if (!names.add(definition.name)) {
        throw ArgumentError('Duplicate rule name detected: ${definition.name}');
      }
    }
  }

  final List<RuleDefinition> _customDefinitions;
  final List<SkillRule> _customRules;

  /// Every rule's check and whether the caller supplied it, in order.
  ///
  /// A rule from `customRules` gets a check whose default severity is the
  /// rule's severity.
  Iterable<({CheckType check, bool isCustom})> get checks sync* {
    for (final CheckType check in RuleRegistry.allChecks) {
      yield (check: check, isCustom: false);
    }
    for (final RuleDefinition definition in _customDefinitions) {
      yield (check: definition.check, isCustom: true);
    }
    for (final SkillRule rule in _customRules) {
      yield (
        check: CheckType(
          name: rule.name,
          defaultSeverity: rule.severity,
          help: 'Custom rule ${rule.name}.',
        ),
        isCustom: true,
      );
    }
  }

  /// The names of every rule in this set.
  Iterable<String> get names => checks.map((c) => c.check.name);

  /// The checks of the rules whose severity and parameters come from the
  /// configuration: the built-in rules and the custom definitions.
  Iterable<CheckType> get configurableChecks => [
    ...RuleRegistry.allChecks,
    for (final RuleDefinition definition in _customDefinitions) definition.check,
  ];

  /// Builds the rules that run under [ruleConfigs], leaving out disabled
  /// rules.
  ///
  /// A rule without an entry in [ruleConfigs] runs at its default severity.
  /// A rule from `customRules` ignores [ruleConfigs].
  ///
  /// Throws an [ArgumentError] when two enabled rules share a name, or when a
  /// configured parameter of a custom definition breaks a constraint.
  List<SkillRule> buildRules(Map<String, RuleConfig> ruleConfigs) {
    final rules = <SkillRule>[];
    final seenNames = <String>{};
    void addRule(SkillRule rule) {
      if (rule.severity == AnalysisSeverity.disabled) {
        return;
      }
      if (!seenNames.add(rule.name)) {
        throw ArgumentError('Duplicate rule name detected: ${rule.name}');
      }
      rules.add(rule);
    }

    for (final CheckType check in RuleRegistry.allChecks) {
      final RuleConfig config = _configFor(check, ruleConfigs);
      final SkillRule? rule = config.severity == AnalysisSeverity.disabled
          ? null
          : RuleRegistry.createRule(check.name, config.severity, config.parameters);
      if (rule != null) {
        addRule(rule);
      }
    }
    for (final RuleDefinition definition in _customDefinitions) {
      final RuleConfig config = _configFor(definition.check, ruleConfigs);
      if (config.severity != AnalysisSeverity.disabled) {
        // TODO(reidbaker-agent): Report unrecognized or mistyped parameters of
        // custom definitions as configuration warnings, as ConfigParser does
        // for built-in rules, instead of throwing.
        final List<String> errors = definition.check.validateConstrainedParameters(
          config.parameters,
        );
        if (errors.isNotEmpty) {
          throw ArgumentError(errors.join('\n'));
        }
        addRule(definition.create(config.severity, config.parameters));
      }
    }
    _customRules.forEach(addRule);
    return rules;
  }

  static RuleConfig _configFor(CheckType check, Map<String, RuleConfig> ruleConfigs) =>
      ruleConfigs[check.name] ?? RuleConfig(severity: check.defaultSeverity);
}
