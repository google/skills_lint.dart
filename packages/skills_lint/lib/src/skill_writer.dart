// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'models/skill_context.dart';
import 'reporters/reporter.dart';

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

/// Writing `SKILL.md` failed. The skill is left as it was.
final class WriteFailed extends ApplyResult {
  WriteFailed(this.error);

  /// The error from the write.
  final Object error;
}

/// Does all of the file I/O for `--fix`: renames a skill directory, then
/// writes its `SKILL.md`.
///
/// Every failure comes back as an [ApplyResult], and this class is the only
/// one that reports it. A new kind of failure only needs a new mapping here.
class SkillWriter {
  SkillWriter(this._reporter);

  final Reporter _reporter;

  /// Checks, without writing, whether [skill] can be renamed to [wantedName].
  ///
  /// It sees a directory that already has the name. It can't see errors that
  /// only the rename itself reveals, such as missing permissions.
  ApplyResult preflight(Directory skill, String wantedName) {
    final RenameBlocked? blocked = _checkTarget(skill, wantedName);
    if (blocked != null) {
      return blocked;
    }
    return Applied(
      Directory(p.join(p.dirname(skill.path), wantedName)),
      renamed: wantedName != p.basename(skill.path),
    );
  }

  /// Renames [skill] to [wantedName], then writes [content] to its
  /// `SKILL.md`.
  ///
  /// When the rename is blocked, nothing is written. When the write fails
  /// after a rename, the rename is undone.
  Future<ApplyResult> apply(Directory skill, String content, String wantedName) async {
    final String currentName = p.basename(skill.path);
    final RenameBlocked? blocked = _checkTarget(skill, wantedName);
    if (blocked != null) {
      return blocked;
    }

    var dir = skill;
    final renamed = wantedName != currentName;
    if (renamed) {
      try {
        dir = await skill.rename(p.join(p.dirname(skill.path), wantedName));
      } on FileSystemException catch (e) {
        _reporter.onRenameFailed(oldSkillName: currentName, targetSkillName: wantedName, error: e);
        return RenameBlocked(target: wantedName, reason: e.message, error: e);
      }
    }

    try {
      await File(p.join(dir.path, SkillContext.skillFileName)).writeAsString(content);
    } on FileSystemException catch (e) {
      if (renamed) {
        await dir.rename(skill.path);
      }
      _reporter.onWriteFailed(skillName: currentName, error: e);
      return WriteFailed(e);
    }
    if (renamed) {
      _reporter.onSkillRenamed(currentName, wantedName);
    }
    return Applied(dir, renamed: renamed);
  }

  /// Reports and returns a [RenameBlocked] when a directory other than
  /// [skill] already has the name [wantedName].
  RenameBlocked? _checkTarget(Directory skill, String wantedName) {
    final String currentName = p.basename(skill.path);
    if (wantedName == currentName) {
      return null;
    }
    final target = Directory(p.join(p.dirname(skill.path), wantedName));
    // On a case-insensitive file system, a name that differs only in case
    // finds the skill directory itself, which is not a clash.
    if (!target.existsSync() ||
        target.resolveSymbolicLinksSync() == skill.resolveSymbolicLinksSync()) {
      return null;
    }
    _reporter.onRenameTargetExists(
      oldSkillName: currentName,
      targetSkillName: wantedName,
      destinationPath: target.path,
    );
    return RenameBlocked(target: wantedName, reason: 'directory $wantedName already exists');
  }
}
