// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'models/skill_context.dart';
import 'models/skill_rule.dart';

/// A rule that `--fix` can apply to a skill's `SKILL.md`.
///
/// Kept internal to the package.
abstract class FixableRule extends SkillRule {
  /// The fixed `SKILL.md` content of the skill that [context] describes.
  ///
  /// [SkillContext.rawContent] holds the content with earlier fixes applied,
  /// and [SkillContext.directoryName] holds the directory name after any
  /// rename a fix plans. Return the content unchanged when there is nothing
  /// to fix.
  ///
  /// `--fix` keeps the result only if it lowers the skill's count of errors,
  /// then warnings, across all enabled rules. So a fix must be idempotent,
  /// and a fix that changes the content must lower this rule's own
  /// diagnostics. Otherwise `--fix` drops it.
  Future<String> fix(SkillContext context);
}
