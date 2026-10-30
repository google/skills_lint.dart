// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'models/skill_context.dart';
import 'models/skill_rule.dart';

/// A rule that can rewrite a skill's `SKILL.md` to clear its own diagnostics.
///
/// Kept internal to the package.
abstract class FixableRule extends SkillRule {
  /// Returns [SkillContext.rawContent] of [context] with this rule's
  /// diagnostics fixed, or unchanged when there is nothing to fix.
  ///
  /// [context] can hold content that earlier fixes changed, and a
  /// [SkillContext.activeDirectoryName] that differs from the name on disk.
  ///
  /// The fixer keeps a fix only if it lowers the skill's errors, then
  /// warnings, across all enabled rules, and it runs fixes until none is
  /// kept. A fix that doesn't lower this rule's own diagnostics is dropped,
  /// and a fix that isn't idempotent can keep changing the skill until the
  /// pass limit.
  Future<String> fix(SkillContext context);
}
