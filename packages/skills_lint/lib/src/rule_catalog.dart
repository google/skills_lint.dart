// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'config_parser.dart';
import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/rule_config.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';
import 'suggestions/levenshtein.dart';

/// The largest edit distance at which a known rule name is suggested for an
/// unknown one.
const int _maxSuggestionDistance = 3;

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

  /// Lists a warning for each rule name in [config] that is not in this
  /// catalog.
  ///
  /// Checks the top-level `rules` map and the `rules` map of every
  /// `directories` and `individual_skills` entry. When a known rule name is
  /// close to the unknown one, the warning suggests it.
  List<String> unknownNameWarnings(Configuration config) {
    final List<String> knownNames = names;
    final Set<String> knownSet = knownNames.toSet();

    final warnings = <String>[];
    void checkRules(Iterable<String> ruleNames, String contextLabel) {
      for (final name in ruleNames) {
        if (knownSet.contains(name)) {
          continue;
        }
        final String? suggestion = _closest(name, knownNames);
        final suggestionClause = suggestion == null ? '' : ' Did you mean "$suggestion"?';
        warnings.add('$contextLabel: Unknown rule "$name".$suggestionClause');
      }
    }

    checkRules(config.ruleConfigs.keys, 'Global rules');
    for (final LintTargetConfig target in config.directoryConfigs) {
      checkRules(target.ruleConfigs.keys, 'Directory entry rules for "${_authoredPath(target)}"');
    }
    for (final LintTargetConfig target in config.individualSkillConfigs) {
      checkRules(
        target.ruleConfigs.keys,
        'Individual skill entry rules for "${_authoredPath(target)}"',
      );
    }
    return warnings;
  }
}

/// Finds the name in [candidates] closest to [name], or `null` when none is
/// within [_maxSuggestionDistance] or two are equally close.
String? _closest(String name, Iterable<String> candidates) {
  String? best;
  int bestDistance = _maxSuggestionDistance + 1;
  var tied = false;
  for (final candidate in candidates) {
    final int distance = levenshtein(name, candidate);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
      tied = false;
    } else if (distance == bestDistance && candidate != best) {
      tied = true;
    }
  }
  return tied ? null : best;
}

/// Reads [target]'s path as written in the configuration file, matching the
/// labels [ConfigParser] uses in its errors.
Object? _authoredPath(LintTargetConfig target) => target.toYaml()[ConfigParser.pathKey];
