// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

/// Stderr messages for `--fix` file operations that the user's files or
/// environment block, identical across output formats.
///
/// Unlike `ToolErrorMessages`, these don't describe a bug in skills_lint.
abstract final class FixIoMessages {
  /// Message for a skill directory that `--fix` can't rename.
  static String renameBlocked({
    required String oldSkillName,
    required String targetSkillName,
    required String reason,
  }) =>
      "Error: could not rename skill directory '$oldSkillName' to '$targetSkillName': $reason.\n"
      "  The directory was left at '$oldSkillName', and the fixes that need the new name were skipped.";

  /// Message for a `SKILL.md` that `--fix` can't write.
  static String writeFailed({required String skillMdPath, required Object error}) =>
      "Error: could not write '$skillMdPath': ${describe(error)}.\n"
      '  The skill was left unchanged.';

  /// Message for a skill directory that `--fix` renamed, then couldn't write
  /// or rename back.
  static String renamedButNotWritten({
    required String fromPath,
    required String toPath,
    required Object writeError,
    required Object undoError,
  }) =>
      "Error: renamed '$fromPath' to '$toPath', but SKILL.md was not written: "
      '${describe(writeError)}.\n'
      '  Renaming the directory back also failed: ${describe(undoError)}.\n'
      "  The skill is at '$toPath' with its old SKILL.md.";

  /// The OS error of [error] when it has one, otherwise [error] as text.
  static String describe(Object error) => switch (error) {
    FileSystemException(osError: OSError(:final String message)) when message.isNotEmpty => message,
    FileSystemException(:final String message) => message,
    _ => '$error',
  };
}
