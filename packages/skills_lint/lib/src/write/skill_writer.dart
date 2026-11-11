// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/skill_context.dart';
import '../reporters/fix_io_messages.dart';
import '../reporters/reporter.dart';
import 'write_boundary.dart';

/// What happened when [SkillWriter] applied, or checked, a fix plan.
sealed class ApplyResult {}

/// The plan was applied, or [SkillWriter.preflight] found nothing that
/// blocks it.
final class Applied extends ApplyResult {
  Applied(this.dir, {required this.renamed});

  /// The skill directory after the plan.
  final Directory dir;

  /// Whether the plan renames the skill directory.
  final bool renamed;
}

/// The skill directory can't take the planned name. Nothing was written.
final class RenameBlocked extends ApplyResult {
  RenameBlocked({required this.target, required this.reason, this.error});

  /// The directory name the plan wanted.
  final String target;

  /// Why the rename can't happen, readable as the end of a sentence.
  final String reason;

  /// The I/O error behind [reason], if there was one.
  final Object? error;
}

/// Writing `SKILL.md` failed, and `SKILL.md` keeps its old content.
final class WriteFailed extends ApplyResult {
  WriteFailed(this.error, {required this.dir});

  /// The error from the write.
  final Object error;

  /// The skill directory after the failure.
  ///
  /// It has the old name, unless undoing the rename failed too.
  final Directory dir;
}

/// The plan would write or rename outside the scan target's
/// [WriteBoundary]. Nothing was written.
final class WriteRefused extends ApplyResult {
  WriteRefused({required this.reason});

  /// Why the write was refused, readable as the end of a sentence.
  final String reason;
}

/// Does all of the file I/O for `--fix`: renames a skill directory, then
/// writes its `SKILL.md`.
///
/// Every failure comes back as an [ApplyResult], and this class is the only
/// one that reports it. A new kind of failure only needs a new mapping here.
class SkillWriter {
  SkillWriter(this._reporter);

  final Reporter _reporter;

  /// Checks, without writing, whether [skill] can be written in place and
  /// renamed to [wantedName] within [boundary].
  ///
  /// It sees a directory that already has the name. It can't see errors that
  /// only the rename itself reveals, such as missing permissions.
  ///
  /// Like [apply], it reports a blocked rename through
  /// [Reporter.onRenameBlocked], and a refused write through
  /// [Reporter.onWriteRefused], so callers don't report them again.
  ApplyResult preflight(Directory skill, String wantedName, WriteBoundary boundary) {
    final ApplyResult? stopped =
        _checkBoundary(skill, wantedName, boundary) ?? _checkTarget(skill, wantedName);
    if (stopped != null) {
      return stopped;
    }
    return Applied(
      Directory(p.join(p.dirname(skill.path), wantedName)),
      renamed: wantedName != p.basename(skill.path),
    );
  }

  /// Renames [skill] to [wantedName], then writes [content] to its
  /// `SKILL.md`.
  ///
  /// When the rename is blocked, or would write outside [boundary], nothing
  /// is written. When the write fails after a rename, the rename is undone if
  /// it can be.
  Future<ApplyResult> apply(
    Directory skill,
    String content,
    String wantedName,
    WriteBoundary boundary,
  ) async {
    final String currentName = p.basename(skill.path);
    final ApplyResult? stopped =
        _checkBoundary(skill, wantedName, boundary) ?? _checkTarget(skill, wantedName);
    if (stopped != null) {
      return stopped;
    }

    var dir = skill;
    final renamed = wantedName != currentName;
    if (renamed) {
      // The check above isn't a guarantee: a directory can appear before the
      // rename, and on POSIX rename(2) replaces an empty one.
      try {
        dir = await skill.rename(p.join(p.dirname(skill.path), wantedName));
      } on FileSystemException catch (e) {
        return _blocked(skill, wantedName, FixIoMessages.describe(e), error: e);
      }
    }

    final skillMd = File(p.join(dir.path, SkillContext.skillFileName));
    try {
      await skillMd.writeAsString(content);
    } on FileSystemException catch (e) {
      if (!renamed) {
        _reporter.onWriteFailed(skillMdPath: skillMd.path, error: e);
        return WriteFailed(e, dir: dir);
      }
      return _undoRenameAfter(e, renamedDir: dir, original: skill);
    }
    if (renamed) {
      _reporter.onSkillRenamed(currentName, wantedName);
    }
    return Applied(dir, renamed: renamed);
  }

  /// Renames [renamedDir] back to [original] after [writeError], and reports
  /// where the skill ends up.
  ///
  /// Undoing the rename keeps the written content and the directory name in
  /// step: the skill keeps its old name and its old `SKILL.md`.
  Future<WriteFailed> _undoRenameAfter(
    FileSystemException writeError, {
    required Directory renamedDir,
    required Directory original,
  }) async {
    try {
      await renamedDir.rename(original.path);
    } on FileSystemException catch (undoError) {
      _reporter.onRenamedButNotWritten(
        fromPath: original.path,
        toPath: renamedDir.path,
        writeError: writeError,
        undoError: undoError,
      );
      return WriteFailed(writeError, dir: renamedDir);
    }
    _reporter.onWriteFailed(
      skillMdPath: p.join(original.path, SkillContext.skillFileName),
      error: writeError,
    );
    return WriteFailed(writeError, dir: original);
  }

  /// Reports and returns a [WriteRefused] when `SKILL.md` would be outside
  /// [boundary], or when [wantedName] differs from [skill]'s directory name and
  /// either cannot be used as a directory name or would land outside
  /// [boundary].
  WriteRefused? _checkBoundary(Directory skill, String wantedName, WriteBoundary boundary) {
    final String currentName = p.basename(skill.path);
    if (wantedName != currentName) {
      final String? badName = WriteBoundary.directoryNameRefusal(wantedName);
      if (badName != null) {
        return _refused(
          action: "rename skill directory '$currentName' to '$wantedName'",
          reason: badName,
        );
      }
    }
    final String skillMdPath = p.join(skill.path, SkillContext.skillFileName);
    final String? writeRefusal = boundary.refusal(skillMdPath);
    if (writeRefusal != null) {
      return _refused(action: "write '$skillMdPath'", reason: writeRefusal);
    }
    if (wantedName == currentName) {
      return null;
    }
    final String renamedPath = p.join(p.dirname(skill.path), wantedName);
    final String? renameRefusal = boundary.refusal(renamedPath);
    if (renameRefusal != null) {
      return _refused(action: "rename '${skill.path}' to '$renamedPath'", reason: renameRefusal);
    }
    return null;
  }

  /// Reports that skills_lint did not [action] because of [reason], and
  /// returns the matching [WriteRefused].
  WriteRefused _refused({required String action, required String reason}) {
    _reporter.onWriteRefused(action: action, reason: reason);
    return WriteRefused(reason: reason);
  }

  /// Reports and returns a [RenameBlocked] when a directory other than
  /// [skill] already has the name [wantedName].
  RenameBlocked? _checkTarget(Directory skill, String wantedName) {
    if (wantedName == p.basename(skill.path)) {
      return null;
    }
    final target = Directory(p.join(p.dirname(skill.path), wantedName));
    try {
      // On a case-insensitive file system, a name that differs only in case
      // finds the skill directory itself, which is not a clash.
      if (!target.existsSync() ||
          target.resolveSymbolicLinksSync() == skill.resolveSymbolicLinksSync()) {
        return null;
      }
    } on FileSystemException catch (e) {
      return _blocked(skill, wantedName, FixIoMessages.describe(e), error: e);
    }
    return _blocked(skill, wantedName, 'directory $wantedName already exists');
  }

  /// Reports that [skill] can't be renamed to [wantedName] because of
  /// [reason], and returns the matching [RenameBlocked].
  RenameBlocked _blocked(Directory skill, String wantedName, String reason, {Object? error}) {
    _reporter.onRenameBlocked(
      oldSkillName: p.basename(skill.path),
      targetSkillName: wantedName,
      reason: reason,
    );
    return RenameBlocked(target: wantedName, reason: reason, error: error);
  }
}
