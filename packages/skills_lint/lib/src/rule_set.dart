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
///
/// Returns `null` when no rule should run.
typedef SkillRuleFactory =
    SkillRule? Function(AnalysisSeverity severity, CustomRuleParameters? parameters);

/// Describes a rule that a configuration can name: its [check] (name, default
/// severity, help text and parameter schema) and how to [create] it.
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
  ///
  /// The configuration's parameters are checked against the constraints in
  /// [check] before [create] runs.
  const RuleDefinition({required this.check, required this.create})
    : isCustom = true,
      _fixedRule = null;

  /// Creates a definition for a built-in rule in [RuleRegistry.allChecks].
  RuleDefinition._builtIn(this.check)
    : create = ((severity, parameters) =>
          RuleRegistry.createRule(check.name, severity, parameters)),
      isCustom = false,
      _fixedRule = null;

  /// Creates a definition that always yields [rule], whatever the
  /// configuration says about it.
  ///
  /// This is how a [SkillRule] passed as `customRules` runs.
  RuleDefinition._fixed(SkillRule rule)
    : check = CheckType(
        name: rule.name,
        defaultSeverity: rule.severity,
        help: 'Custom rule ${rule.name}.',
      ),
      create = ((_, _) => rule),
      isCustom = true,
      _fixedRule = rule;

  /// The rule's name, default severity, help text and parameter schema.
  final CheckType check;

  /// Builds the rule from its configured severity and parameters.
  final SkillRuleFactory create;

  /// Whether the caller supplied this rule rather than `skills_lint`.
  final bool isCustom;

  /// The rule that a definition from `customRules` always yields.
  final SkillRule? _fixedRule;

  /// The rule's name, as written in configuration.
  String get name => check.name;

  /// Whether the configuration sets this rule's severity and parameters.
  ///
  /// A rule passed as `customRules` is not configurable.
  bool get isConfigurable => _fixedRule == null;
}

/// The rules one validation run knows about: every built-in rule, then the
/// caller's custom rules.
///
/// Building, reporting and checking configured rule names all read this one
/// list.
final class RuleSet {
  /// Creates a set of the built-in rules plus [customDefinitions] and
  /// [customRules].
  RuleSet({
    List<RuleDefinition> customDefinitions = const [],
    List<SkillRule> customRules = const [],
  }) : definitions = List.unmodifiable([
         for (final CheckType check in RuleRegistry.allChecks) RuleDefinition._builtIn(check),
         ...customDefinitions,
         for (final SkillRule rule in customRules) RuleDefinition._fixed(rule),
       ]);

  /// Built-in rules first, then custom rules, in the order given.
  final List<RuleDefinition> definitions;

  /// The names of every rule in this set.
  Iterable<String> get names => definitions.map((RuleDefinition d) => d.name);

  /// Builds the rules that run under [ruleConfigs], leaving out disabled
  /// rules.
  ///
  /// A rule without an entry in [ruleConfigs] runs at its default severity.
  /// A rule from `customRules` ignores [ruleConfigs].
  ///
  /// Throws an [ArgumentError] when two enabled rules share a name, or when a
  /// configured parameter breaks a constraint of its rule.
  List<SkillRule> buildRules(Map<String, RuleConfig> ruleConfigs) {
    final rules = <SkillRule>[];
    final seenNames = <String>{};
    for (final RuleDefinition definition in definitions) {
      final SkillRule? rule = _build(definition, ruleConfigs);
      if (rule == null || rule.severity == AnalysisSeverity.disabled) {
        continue;
      }
      if (!seenNames.add(rule.name)) {
        throw ArgumentError('Duplicate rule name detected: ${rule.name}');
      }
      rules.add(rule);
    }
    return rules;
  }

  static SkillRule? _build(RuleDefinition definition, Map<String, RuleConfig> ruleConfigs) {
    if (!definition.isConfigurable) {
      return definition._fixedRule;
    }
    final RuleConfig config =
        ruleConfigs[definition.name] ?? RuleConfig(severity: definition.check.defaultSeverity);
    if (config.severity == AnalysisSeverity.disabled) {
      return null;
    }
    final CustomRuleParameters parameters = config.parameters;
    // TODO(reidbaker-agent): Report unrecognized or mistyped parameters of custom
    // definitions as configuration warnings. ConfigParser checks only built-in rules.
    if (definition.isCustom) {
      final List<String> errors = definition.check.validateConstrainedParameters(parameters);
      if (errors.isNotEmpty) {
        throw ArgumentError(errors.join('\n'));
      }
    }
    return definition.create(config.severity, parameters);
  }
}
