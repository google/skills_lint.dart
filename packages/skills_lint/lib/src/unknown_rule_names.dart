// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wording for configured rule names that match no built-in rule.
library;

import 'models/rule_config.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';
import 'suggestions/closest_name.dart';
import 'validator.dart';

/// The rule names a configuration can set: every built-in check, and
/// [Validator.skillFileInaccessible], whose severity the validator also reads.
final Set<String> configurableRuleNames = {
  ...RuleRegistry.ruleNames,
  Validator.skillFileInaccessible,
};

/// Describes [name], a configured rule name that is not in
/// [configurableRuleNames], for `Configuration.parsingErrors`.
///
/// [context] labels where [name] is, such as `Global rules`. [location] is
/// `file:line` when the configuration came from a file. The message offers
/// the closest configurable names. When none is close, it says the name may
/// come from a newer skills_lint.
String unknownRuleNameMessage(String name, {required String context, String? location}) {
  final List<String> suggestions = closestNames(
    name,
    configurableRuleNames,
    maxDistance: typoDistanceLimit(name),
  );
  final where = location == null ? '' : ' ($location)';
  final hint = suggestions.isEmpty
      ? ' If it is a rule from a newer skills_lint, upgrade skills_lint.'
      : ' ${_didYouMean(suggestions)}';
  return '$context: Unknown rule "$name"$where.$hint';
}

/// Describes each key of [overrides] that is not in [configurableRuleNames].
///
/// Configuration has no effect on custom rules, so a key that names one of
/// [customRules] gets a message that says so instead.
List<String> unknownOverrideMessages(
  Map<String, RuleConfigPatch> overrides,
  List<SkillRule> customRules,
) {
  final Set<String> customNames = {for (final rule in customRules) rule.name};
  const context = 'resolvedRuleConfigs';
  return [
    for (final String name in overrides.keys)
      if (customNames.contains(name))
        '$context: "$name" is a custom rule, and configuration has no effect on '
            'custom rules (https://github.com/google/skills_lint.dart/issues/163). '
            'Set its severity on the rule object.'
      else if (!configurableRuleNames.contains(name))
        unknownRuleNameMessage(name, context: context),
  ];
}

/// Formats [names] as a question, such as `Did you mean "a"?` or
/// `Did you mean "a" or "b"?`. [names] must not be empty.
String _didYouMean(List<String> names) {
  final List<String> quoted = [for (final name in names) '"$name"'];
  final String choices = switch (quoted) {
    [] => throw ArgumentError.value(names, 'names', 'must not be empty'),
    [final only] => only,
    [final first, final second] => '$first or $second',
    [...final others, final last] => '${others.join(', ')}, or $last',
  };
  return 'Did you mean $choices?';
}
