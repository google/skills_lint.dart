// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'config_parser.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';
import 'suggestions/closest_name.dart';

/// A rule name in a configuration that is neither a built-in rule nor a
/// custom rule.
@immutable
class UnknownRuleName {
  /// Creates a finding for [name], found in the rules map that [context]
  /// labels, with an optional [suggestion].
  const UnknownRuleName({required this.context, required this.name, this.suggestion});

  /// The label of the rules map [name] appears in, such as
  /// [ConfigParser.globalRulesLabel].
  final String context;

  /// The rule name as written.
  final String name;

  /// The known rule name closest to [name], or `null` when none is close.
  final String? suggestion;

  /// The text shown to the user.
  String get message =>
      '$context: Unknown rule "$name".${suggestion == null ? '' : ' Did you mean "$suggestion"?'}';
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

  Iterable<UnknownRuleName> check(Iterable<String> ruleNames, String context) => [
    for (final name in ruleNames)
      if (!knownSet.contains(name))
        UnknownRuleName(context: context, name: name, suggestion: closestName(name, knownNames)),
  ];

  return [
    ...check(config.ruleConfigs.keys, ConfigParser.globalRulesLabel),
    for (final LintTargetConfig target in config.directoryConfigs)
      ...check(
        target.ruleConfigs.keys,
        ConfigParser.entryRulesLabel(ConfigParser.directoriesKey, _authoredPath(target)),
      ),
    for (final LintTargetConfig target in config.individualSkillConfigs)
      ...check(
        target.ruleConfigs.keys,
        ConfigParser.entryRulesLabel(ConfigParser.individualSkillsKey, _authoredPath(target)),
      ),
  ];
}

/// Reads [target]'s path as written in the configuration file, matching the
/// labels [ConfigParser] uses in its errors.
Object? _authoredPath(LintTargetConfig target) => target.toYaml()[ConfigParser.pathKey];
