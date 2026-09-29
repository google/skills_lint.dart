// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'reporter.dart';

/// Stderr messages for internal tool failures.
///
/// Every output format writes these to stderr with the same text, so they
/// are built here once instead of in each [Reporter].
abstract final class ToolErrorMessages {
  /// Line shared by every internal-error message, telling the user that the
  /// fault is in the tool and not in their skill.
  static const String _toolBugNotice =
      '  This is a bug in skills_lint, not a problem with your skill.';

  /// The stderr message every format writes for [Reporter.onFixFailed].
  static String fixFailedMessage({required String ruleName, required Object error}) =>
      "${Reporter.toolErrorPrefix} could not apply the '$ruleName' fix.\n"
      '$_toolBugNotice\n'
      '  Your skill was left unmodified. Cause: $error';

  /// The stderr message every format writes for [Reporter.onRenameFailed].
  static String renameFailedMessage({
    required String oldSkillName,
    required String targetSkillName,
    required Object error,
  }) =>
      "${Reporter.toolErrorPrefix} could not rename skill directory from '$oldSkillName' to '$targetSkillName'.\n"
      '$_toolBugNotice\n'
      "  Your skill directory was left at '$oldSkillName'. Cause: $error";

  /// The stderr message every format writes for [Reporter.onRenameTargetExists].
  static String renameTargetExistsMessage({
    required String oldSkillName,
    required String targetSkillName,
    required String destinationPath,
  }) =>
      "${Reporter.toolErrorPrefix} cannot rename skill directory from '$oldSkillName' to '$targetSkillName': destination directory '$destinationPath' already exists.\n"
      '$_toolBugNotice\n'
      "  Your skill directory was left at '$oldSkillName'.";

  /// The stderr message every format writes for [Reporter.onBaselineFailed].
  static String baselineFailedMessage(String ignorePath, Object error) =>
      "${Reporter.toolErrorPrefix} failed to generate baseline file at '$ignorePath'.\n"
      '$_toolBugNotice\n'
      '  Your baseline file was left unmodified. Cause: $error';
}
