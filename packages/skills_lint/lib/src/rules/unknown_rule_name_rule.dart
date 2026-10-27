// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../models/analysis_severity.dart';

/// The names and defaults of the `unknown-rule-name` rule, which reports a
/// rule name in `skills_lint.yaml` that names no built-in or custom rule.
///
/// The rule checks the configuration, not a skill, so it has no
/// `SkillRule` class. `ValidationSession.reportUnknownRuleNames` runs it
/// once per run, with the severity and parameters from the top-level
/// `rules` map and the command line.
abstract final class UnknownRuleNameRule {
  /// The rule's name.
  static const String ruleName = 'unknown-rule-name';

  /// The parameter that lists rule names to accept, such as rules that only
  /// a newer skills_lint has.
  static const String allowParameter = 'allow';

  // TODO(reidbaker-agent): https://github.com/google/skills_lint.dart/issues/155
  // Change the default to error in 0.6.0.
  /// The rule's default severity.
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;
}
