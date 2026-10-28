// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../config_locator.dart';
import '../config_parser.dart';
import '../models/analysis_severity.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import '../suggestions/closest_name.dart';
import '../unknown_rule_names.dart';

/// Checks that every rule name in `skills_lint.yaml` names a built-in rule or
/// a custom rule.
///
/// Unlike a [SkillRule], which runs on each skill directory, this rule checks
/// the [Configuration] once per session, with the severity and [allowed] names
/// from the top-level `rules` map and the command line.
class UnknownRuleNameRule {
  UnknownRuleNameRule({this.severity = defaultSeverity, Iterable<String> allowed = const []})
    : allowed = List.unmodifiable(allowed);

  /// The rule's name.
  static const String ruleName = 'unknown-rule-name';

  /// The parameter that lists rule names to accept, such as rules that only
  /// a newer skills_lint has.
  static const String allowParameter = 'allow';

  // TODO(reidbaker-agent): https://github.com/google/skills_lint.dart/issues/155
  // Change the default to error in 0.6.0.
  /// The rule's default severity.
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  /// The severity of findings this rule produces.
  final AnalysisSeverity severity;

  /// Rule names to accept even when they match no built-in or custom rule.
  final List<String> allowed;

  /// Validates the rule names in [config] against the built-in rules,
  /// [customRules], and [allowed].
  ///
  /// [configFile] is the file [config] was loaded from. When it is given,
  /// each finding points to the line of its rule name. Without it, such as
  /// for a configuration parsed from a string, findings have no line.
  List<ValidationError> validate(
    Configuration config, {
    List<SkillRule> customRules = const [],
    String? configFile,
  }) {
    if (severity == AnalysisSeverity.disabled) {
      return const [];
    }
    final String file = configFile ?? 'skills_lint.yaml';
    return [
      for (final UnknownRuleName finding in findUnknownRuleNames(
        config,
        customRules,
        allowed: allowed,
      ))
        ValidationError(
          ruleId: ruleName,
          file: file,
          message: formatMessage(finding),
          severity: severity,
          region: switch (configFile == null ? null : lineOfRuleKey(configFile, finding.key)) {
            null => null,
            final int line => SourceRegion(startLine: line),
          },
        ),
    ];
  }

  /// Builds the plain-text message for [finding], such as
  /// `Global rules: Unknown rule "x". Did you mean "y"?`.
  ///
  /// Reporters decide how to present it; this only builds the text.
  static String formatMessage(UnknownRuleName finding) =>
      '${finding.context}: Unknown rule "${finding.name}".'
      '${finding.suggestions.isEmpty ? '' : ' ${didYouMean(finding.suggestions)}'}';
}
