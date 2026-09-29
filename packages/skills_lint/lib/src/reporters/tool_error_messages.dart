// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'reporter.dart';

/// Stderr messages for internal tool failures, identical across output formats.
abstract final class ToolErrorMessages {
  /// Line shared by every internal-error message, telling the user that the
  /// fault is in the tool and not in their skill.
  static const String _toolBugNotice =
      '  This is a bug in skills_lint, not a problem with your skill.';

  /// Message for a rule fix that failed and left the skill unmodified.
  static String fixFailedMessage({required String ruleName, required Object error}) =>
      "${Reporter.toolErrorPrefix} could not apply the '$ruleName' fix.\n"
      '$_toolBugNotice\n'
      '  Your skill was left unmodified. Cause: $error';

  /// Message for a skill directory rename that failed.
  static String renameFailedMessage({
    required String oldSkillName,
    required String targetSkillName,
    required Object error,
  }) =>
      "${Reporter.toolErrorPrefix} could not rename skill directory from '$oldSkillName' to '$targetSkillName'.\n"
      '$_toolBugNotice\n'
      "  Your skill directory was left at '$oldSkillName'. Cause: $error";

  /// Message for a skill directory rename blocked by an existing destination.
  static String renameTargetExistsMessage({
    required String oldSkillName,
    required String targetSkillName,
    required String destinationPath,
  }) =>
      "${Reporter.toolErrorPrefix} cannot rename skill directory from '$oldSkillName' to '$targetSkillName': destination directory '$destinationPath' already exists.\n"
      '$_toolBugNotice\n'
      "  Your skill directory was left at '$oldSkillName'.";

  /// Message for a baseline file that could not be written.
  static String baselineFailedMessage({required String ignorePath, required Object error}) =>
      "${Reporter.toolErrorPrefix} failed to generate baseline file at '$ignorePath'.\n"
      '$_toolBugNotice\n'
      '  Your baseline file was left unmodified. Cause: $error';
}
