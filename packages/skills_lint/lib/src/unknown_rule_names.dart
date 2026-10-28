// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'config_parser.dart';
import 'models/rule_config.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';
import 'suggestions/closest_name.dart';

/// A rule name in a configuration that is neither a built-in rule nor a
/// custom rule.
@immutable
class UnknownRuleName {
  /// Creates a finding for [name], found in the rules map that [context]
  /// labels, with any [suggestions] and an optional 1-based [line].
  const UnknownRuleName({
    required this.context,
    required this.name,
    this.suggestions = const [],
    this.line,
  });

  /// The label of the rules map [name] appears in, such as `'Global rules'`.
  final String context;

  /// The rule name as written.
  final String name;

  /// The known rule names closest to [name], sorted, or empty when none is
  /// close.
  ///
  /// Built-in and custom rule names are treated alike. When several are
  /// equally close, all of them are listed. See [closestNames].
  final List<String> suggestions;

  /// The 1-based line of [name] in the configuration file, or `null` when the
  /// configuration was built in memory rather than parsed from YAML.
  final int? line;
}

/// Finds each rule name in [config] that is neither a built-in rule, one of
/// [customRules], nor in [allowed].
///
/// Checks the top-level `rules` map and the `rules` map of every
/// `directories` and `individual_skills` entry. [ConfigParser] cannot do this
/// check, because it does not know which custom rules the caller passes.
List<UnknownRuleName> findUnknownRuleNames(
  Configuration config,
  List<SkillRule> customRules, {
  Iterable<String> allowed = const [],
}) {
  final List<String> knownNames = [
    for (final check in RuleRegistry.allChecks) check.name,
    for (final rule in customRules) rule.name,
  ];
  final knownSet = {...knownNames, ...allowed};

  Iterable<UnknownRuleName> check(Map<String, RuleConfigPatch> rules, String context) => [
    for (final MapEntry(key: name, value: patch) in rules.entries)
      if (!knownSet.contains(name))
        UnknownRuleName(
          context: context,
          name: name,
          suggestions: closestNames(name, knownNames, maxDistance: thirdOfLength(name)),
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

/// Reads [target]'s path as written in the configuration file, matching the
/// labels [ConfigParser] uses in its errors.
Object? _authoredPath(LintTargetConfig target) => target.toYaml()[ConfigParser.pathKey];
