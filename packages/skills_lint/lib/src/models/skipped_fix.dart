// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A fix that the fixer tried and dropped because it would not make the
/// skill better.
class SkippedFix {
  SkippedFix({
    required this.ruleName,
    required this.grownRuleNames,
    this.reason,
    this.needsRename = false,
  });

  /// The rule whose fix was dropped.
  final String ruleName;

  /// The rules that would report more diagnostics after the fix.
  ///
  /// Empty when the fix only failed to lower the count.
  final List<String> grownRuleNames;

  /// Why the fix was dropped, when the fixer's counts don't say it, such as
  /// a directory rename that can't happen.
  final String? reason;

  /// Whether the fix was dropped because it changes the skill's `name`, and
  /// the skill directory can't be renamed to match.
  final bool needsRename;

  /// A copy of this skipped fix with [reason].
  SkippedFix withReason(String reason) => SkippedFix(
    ruleName: ruleName,
    grownRuleNames: grownRuleNames,
    reason: reason,
    needsRename: needsRename,
  );
}
