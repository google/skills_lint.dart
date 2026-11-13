// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wording for configured rule names that match no built-in rule.
///
/// @docImport 'config_parser.dart';
library;

import 'models/rule_config.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';
import 'suggestions/did_you_mean.dart';
import 'validator.dart';

/// The rule names that a configuration can set.
///
/// These are the built-in checks plus [Validator.skillFileInaccessible].
/// That one is not a check, but the validator reads its severity.
Set<String> get configurableRuleNames => {
  ...RuleRegistry.ruleNames,
  Validator.skillFileInaccessible,
};

/// Describes [name], a configured rule name that is not in
/// [configurableRuleNames], for `Configuration.parsingErrors`.
///
/// The message offers the closest configurable names. When none is close, it
/// says the name may come from a newer skills_lint.
///
/// [context] labels where [name] is, such as `Global rules`. Leave it out
/// when the message carries a file location instead.
String unknownRuleNameMessage(String name, {String? context}) {
  final String hint =
      didYouMeanClosest(name, configurableRuleNames) ??
      'If it is a rule from a newer skills_lint, upgrade skills_lint.';
  return '${_prefix(context)}unknown rule "$name". $hint';
}

/// Describes a plain `<<` key in a rules map. package:yaml does not support
/// YAML merge keys, so it reads `<<` as a rule name.
///
/// [context] labels where the key is, as for [unknownRuleNameMessage].
String mergeKeyMessage({String? context}) =>
    '${_prefix(context)}YAML merge keys ("<<") are not supported; '
    "write out each rule's settings.";

/// Describes each name in [rules] that is not in [configurableRuleNames].
///
/// For rules that a caller supplies in code, such as `resolvedRuleConfigs` or
/// a [Configuration] built without [ConfigParser]. [context] labels where
/// [rules] came from. Configuration has no effect on custom rules, so a name
/// of one of [customRules] gets a message that says so instead.
List<String> unknownRuleMessages(
  Map<String, RuleConfigPatch> rules, {
  required String context,
  required List<SkillRule> customRules,
}) {
  final Set<String> customNames = {for (final rule in customRules) rule.name};
  return [
    for (final String name in rules.keys)
      if (customNames.contains(name))
        '$context: "$name" is a custom rule, and configuration has no effect on '
            'custom rules (https://github.com/google/skills_lint.dart/issues/163). '
            'Set its severity on the rule object.'
      else if (!configurableRuleNames.contains(name))
        unknownRuleNameMessage(name, context: context),
  ];
}

String _prefix(String? context) => context == null ? '' : '$context: ';
