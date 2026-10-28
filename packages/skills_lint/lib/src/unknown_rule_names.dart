// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'config_locator.dart';
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
  /// labels, with any [suggestions], at [key].
  const UnknownRuleName({
    required this.context,
    required this.name,
    this.suggestions = const [],
    required this.key,
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

  /// Where [name] sits in the configuration, for [lineOfRuleKey].
  final RuleKeyPath key;
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

  Iterable<UnknownRuleName> check(
    Map<String, RuleConfigPatch> rules,
    String context, {
    required String section,
    int? entryIndex,
  }) => [
    for (final String name in rules.keys)
      if (!knownSet.contains(name))
        UnknownRuleName(
          context: context,
          name: name,
          suggestions: closestNames(name, knownNames, maxDistance: thirdOfLength(name)),
          key: (section: section, entryIndex: entryIndex, ruleName: name),
        ),
  ];

  return [
    ...check(config.ruleConfigs, 'Global rules', section: ConfigParser.rulesKey),
    for (final (int i, LintTargetConfig target) in config.directoryConfigs.indexed)
      ...check(
        target.ruleConfigs,
        'Directory entry rules for "${_authoredPath(target)}"',
        section: ConfigParser.directoriesKey,
        entryIndex: i,
      ),
    for (final (int i, LintTargetConfig target) in config.individualSkillConfigs.indexed)
      ...check(
        target.ruleConfigs,
        'Individual skill entry rules for "${_authoredPath(target)}"',
        section: ConfigParser.individualSkillsKey,
        entryIndex: i,
      ),
  ];
}

/// Reads [target]'s path as written in the configuration file, matching the
/// labels [ConfigParser] uses in its errors.
Object? _authoredPath(LintTargetConfig target) => target.toYaml()[ConfigParser.pathKey];
