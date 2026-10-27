// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'config_parser.dart';
import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/rule_config.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';
import 'suggestions/closest_name.dart';

/// The rules one validation run can use: the built-in checks in
/// [RuleRegistry.allChecks] and the caller's [customRules].
///
/// [Configuration] holds only what round-trips to YAML, so it cannot hold
/// [SkillRule] objects. Code that needs every rule takes a [RuleCatalog]
/// instead of a separate list of custom rules.
class RuleCatalog {
  /// Creates a catalog of the built-in checks and [customRules].
  const RuleCatalog({this.customRules = const []});

  /// The rules the caller supplied, in the order given. The list is not
  /// copied.
  final List<SkillRule> customRules;

  /// The built-in checks, in registry order. Every catalog has the same ones.
  List<CheckType> get builtInChecks => RuleRegistry.allChecks;

  /// The names of every built-in check and custom rule, built-ins first.
  List<String> get names => [
    for (final CheckType check in builtInChecks) check.name,
    for (final SkillRule rule in customRules) rule.name,
  ];

  /// Creates the enabled rules: each built-in check configured by
  /// [ruleConfigs] (or its default), then each custom rule.
  ///
  /// Leaves out rules whose severity is [AnalysisSeverity.disabled]. Throws an
  /// [ArgumentError] if two enabled rules share a name.
  List<SkillRule> activeRules(Map<String, RuleConfig> ruleConfigs) {
    final rules = <SkillRule>[];
    final seenNames = <String>{};

    void addRule(SkillRule rule) {
      if (rule.severity != AnalysisSeverity.disabled) {
        if (!seenNames.add(rule.name)) {
          throw ArgumentError('Duplicate rule name detected: ${rule.name}');
        }
        rules.add(rule);
      }
    }

    for (final CheckType check in builtInChecks) {
      final RuleConfig config =
          ruleConfigs[check.name] ?? RuleConfig(severity: check.defaultSeverity);
      if (config.severity != AnalysisSeverity.disabled) {
        final SkillRule? rule = RuleRegistry.createRule(
          check.name,
          config.severity,
          config.parameters,
        );
        if (rule != null) {
          addRule(rule);
        }
      }
    }

    customRules.forEach(addRule);

    return rules;
  }

  /// Finds each rule name in [config] that is neither in this catalog nor in
  /// [allowed].
  ///
  /// Checks the top-level `rules` map and the `rules` map of every
  /// `directories` and `individual_skills` entry.
  List<UnknownRuleName> findUnknownNames(
    Configuration config, {
    Iterable<String> allowed = const [],
  }) {
    final List<String> knownNames = names;
    final knownSet = {...knownNames, ...allowed};

    Iterable<UnknownRuleName> check(Map<String, RuleConfigPatch> ruleConfigs, String context) => [
      for (final MapEntry(key: name, value: patch) in ruleConfigs.entries)
        if (!knownSet.contains(name))
          UnknownRuleName(
            context: context,
            name: name,
            suggestion: closestName(name, knownNames),
            line: ruleLineOf(patch),
          ),
    ];

    return [
      ...check(config.ruleConfigs, 'Global rules'),
      for (final LintTargetConfig target in config.directoryConfigs)
        ...check(target.ruleConfigs, 'Directory entry rules for "${_authoredPath(target)}"'),
      for (final LintTargetConfig target in config.individualSkillConfigs)
        ...check(target.ruleConfigs, 'Individual skill entry rules for "${_authoredPath(target)}"'),
    ];
  }
}

/// A rule name in a configuration that is not in a [RuleCatalog].
@immutable
class UnknownRuleName {
  /// Creates a finding for [name], found in the rules map that [context]
  /// labels, with an optional [suggestion] and 1-based YAML [line].
  const UnknownRuleName({required this.context, required this.name, this.suggestion, this.line});

  /// The label of the rules map [name] appears in, such as `'Global rules'`.
  final String context;

  /// The rule name as written.
  final String name;

  /// The known rule name closest to [name], or `null` when none is close.
  ///
  /// Built-in and custom rule names are treated alike: when two are equally
  /// close, there is no suggestion. See [closestName].
  final String? suggestion;

  /// The 1-based line number of [name] in the configuration file, or `null`
  /// when the configuration was constructed in memory without YAML spans.
  final int? line;
}

/// Reads [target]'s path as written in the configuration file, matching the
/// labels [ConfigParser] uses in its errors.
Object? _authoredPath(LintTargetConfig target) => target.toYaml()[ConfigParser.pathKey];
