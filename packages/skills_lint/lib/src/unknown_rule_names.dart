// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:logging/logging.dart';

import 'config_parser.dart';
import 'models/skill_rule.dart';
import 'rule_registry.dart';
import 'suggestions/levenshtein.dart';

final _log = Logger('skills_lint');

/// The largest edit distance at which a known rule name is suggested for an
/// unknown one.
const int _maxSuggestionDistance = 3;

/// Returns one message for each rule name in [config] that is neither a
/// built-in rule nor one of [customRules].
///
/// Checks the top-level `rules` map and the `rules` map of every
/// `directories` and `individual_skills` entry. [ConfigParser] cannot do this
/// check, because it does not know which custom rules the caller passes.
///
/// When a known rule name is close to the unknown one, the message suggests
/// it.
List<String> unknownRuleNameWarnings(Configuration config, List<SkillRule> customRules) {
  final List<String> knownNames = [
    for (final check in RuleRegistry.allChecks) check.name,
    for (final rule in customRules) rule.name,
  ];
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

/// Logs each of [unknownRuleNameWarnings] for [config] as a
/// `Configuration warning:` at [Level.WARNING]. Does nothing when [config] is `null`.
void logUnknownRuleNameWarnings(Configuration? config, List<SkillRule> customRules) {
  if (config == null) {
    return;
  }
  for (final String warning in unknownRuleNameWarnings(config, customRules)) {
    _log.warning('Configuration warning: $warning');
  }
}

/// Returns the name in [candidates] closest to [name], or `null` when none is
/// within [_maxSuggestionDistance] or two are equally close.
String? _closest(String name, List<String> candidates) {
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

/// Returns [target]'s path as written in the configuration file, matching the
/// labels [ConfigParser] uses in its errors.
Object? _authoredPath(LintTargetConfig target) => target.toYaml()[ConfigParser.pathKey];
