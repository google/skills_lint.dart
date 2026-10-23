// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A fix that the fixer tried and dropped because it would not make the
/// skill better.
class SkippedFix {
  SkippedFix({required this.ruleName, required this.grownRuleNames, this.blockedDirectoryName});

  /// The rule whose fix was dropped.
  final String ruleName;

  /// The rules that would report more diagnostics after the fix.
  ///
  /// Empty when the fix only failed to lower the count.
  final List<String> grownRuleNames;

  /// The directory name the fix would rename the skill to, when a directory
  /// with that name already exists.
  final String? blockedDirectoryName;
}
