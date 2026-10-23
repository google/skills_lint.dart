// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'skill_context.dart';
import 'skipped_fix.dart';
import 'validation_result.dart';

/// The state the fixer reaches for one skill, before anything is written.
class FixOutcome {
  FixOutcome({
    required this.result,
    required this.appliedRuleNames,
    required this.skippedFixes,
    required this.settled,
    this.blockedDirectoryName,
  });

  /// The validation result of the fixed content.
  ///
  /// Its context holds the fixed content and the planned directory name.
  final ValidationResult result;

  /// The rules whose fixes were kept, in the order they first applied.
  final List<String> appliedRuleNames;

  /// The fixes that were dropped, for rules that still report diagnostics.
  final List<SkippedFix> skippedFixes;

  /// Whether a last pass over the rules kept no fix.
  ///
  /// False when the pass limit ended the loop, which only a fix that changes
  /// between identical calls can cause.
  final bool settled;

  /// The directory name a kept fix would rename the skill to, when another
  /// directory already has that name. The fixed content is judged under the
  /// current name instead.
  final String? blockedDirectoryName;

  SkillContext get _context => result.context!;

  /// The fixed `SKILL.md` content.
  String get content => _context.rawContent;

  /// The directory name after the fixes, which differs from the current one
  /// when a fix renames the skill.
  String get directoryName => _context.activeDirectoryName;
}
