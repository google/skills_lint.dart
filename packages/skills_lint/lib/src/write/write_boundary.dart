// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../path_utils.dart';
import '../reporters/fix_io_messages.dart';

/// The directory that skills_lint may write in for one scan target.
///
/// The files under a scan target choose paths that `--fix` and
/// `--generate-baseline` write to: directory names,
/// frontmatter `name` values, symlinks, and the target's `skills_lint.yaml`.
/// Every such write and rename is checked here, after symlinks are resolved,
/// so that content in a scanned repository can't reach files outside it.
@immutable
final class WriteBoundary {
  /// A boundary at the absolute path [directory], widened to the absolute
  /// directories in [allowed].
  const WriteBoundary(String this.directory, {this.allowed = const []})
    : _unresolvableReason = null;

  /// No boundary, for a path the user named on the command line or through
  /// the API.
  const WriteBoundary.none() : directory = null, allowed = const [], _unresolvableReason = null;

  /// A boundary that refuses every write because the scan target or boundary
  /// itself could not be resolved on disk.
  const WriteBoundary._unresolvable(String this._unresolvableReason)
    : directory = null,
      allowed = const [];

  /// The boundary for the skills directory at the absolute path [directory]:
  /// [directory] itself.
  ///
  /// [configDirectory] is the directory of the configuration file that declared
  /// [directory], if any; [configAllowed] holds `write_allow` directories from
  /// that entry; and [allowed] holds directories from `--allow-write`.
  factory WriteBoundary.forSkillsDirectory(
    String directory, {
    String? configDirectory,
    List<String> configAllowed = const [],
    List<String> allowed = const [],
  }) => _confined(
    directory,
    boundary: directory,
    configDirectory: configDirectory,
    configAllowed: configAllowed,
    allowed: allowed,
  );

  /// The boundary for the individual skill at the absolute path [skill]: the
  /// directory that holds the skill after symlinks are resolved, so that
  /// `--fix` can rename the skill next to where it is.
  ///
  /// When [skill] came from a configuration file and its parent directory sits
  /// outside [configDirectory] (for example `individual_skills: [{path: .}]`),
  /// the boundary stays at [configDirectory] so writes cannot escape the
  /// configuration file's directory.
  factory WriteBoundary.forSkill(
    String skill, {
    String? configDirectory,
    List<String> configAllowed = const [],
    List<String> allowed = const [],
  }) {
    final String resolvedSkill;
    try {
      resolvedSkill = resolveSymlinks(skill);
    } on FileSystemException catch (e) {
      return WriteBoundary._unresolvable(_cannotResolve(skill, e));
    }
    return _confined(
      skill,
      boundary: p.dirname(resolvedSkill),
      configDirectory: configDirectory,
      configAllowed: configAllowed,
      allowed: allowed,
    );
  }

  /// A [WriteBoundary] at [boundary] for a scan target at [target].
  ///
  /// Both [target] and [boundary] must stay at or inside [configDirectory] when
  /// [configDirectory] is set; otherwise the boundary falls back to
  /// [configDirectory].
  static WriteBoundary _confined(
    String target, {
    required String boundary,
    required String? configDirectory,
    required List<String> configAllowed,
    required List<String> allowed,
  }) {
    final allAllowed = [...allowed, ...configAllowed];
    if (configDirectory == null) {
      return WriteBoundary(boundary, allowed: allAllowed);
    }
    try {
      final String realConfigDirectory = resolveSymlinks(configDirectory);
      final String realTarget = resolveSymlinks(target);
      final String realBoundary = resolveSymlinks(boundary);
      if (isAtOrWithin(realConfigDirectory, realTarget) &&
          isAtOrWithin(realConfigDirectory, realBoundary)) {
        return WriteBoundary(boundary, allowed: allAllowed);
      }
      return WriteBoundary(configDirectory, allowed: allAllowed);
    } on FileSystemException catch (e) {
      return WriteBoundary._unresolvable(_cannotResolve(target, e));
    }
  }

  /// The absolute directory that writes must stay inside, or `null` when
  /// unbounded or [_unresolvableReason] is set.
  final String? directory;

  /// Absolute directories outside [directory] that writes may also land in,
  /// from `write_allow` and `--allow-write`.
  final List<String> allowed;

  final String? _unresolvableReason;

  /// Why writing or creating [path] is refused, readable as the end of a
  /// sentence, or `null` when [path] is inside the boundary.
  String? refusal(String path) {
    if (_unresolvableReason != null) {
      return _unresolvableReason;
    }
    final String? root = directory;
    if (root == null) {
      return null;
    }
    final String realRoot;
    final String realPath;
    try {
      realRoot = resolveSymlinks(root);
      realPath = resolveSymlinks(path);
    } on FileSystemException catch (e) {
      return _cannotResolve(path, e);
    }
    if (p.isWithin(realRoot, realPath) || _isWithinAllowed(realPath)) {
      return null;
    }
    if (p.equals(realPath, p.normalize(path))) {
      return "it is outside '$realRoot'";
    }
    return "it resolves to '$realPath', outside '$realRoot'";
  }

  bool _isWithinAllowed(String realPath) {
    for (final String directory in allowed) {
      try {
        if (isAtOrWithin(resolveSymlinks(directory), realPath)) {
          return true;
        }
      } on FileSystemException {
        // An unresolvable `--allow-write` directory grants no access.
      }
    }
    return false;
  }

  static String _cannotResolve(String path, FileSystemException error) =>
      "could not resolve '$path' (${FixIoMessages.describe(error)})";

  /// Why [name] cannot be used as a skill directory name, readable as the end
  /// of a sentence, or `null` when [name] is a valid directory name.
  static String? directoryNameRefusal(String name) {
    if (name.isEmpty) {
      return 'the skill name is empty';
    }
    if (name == '.' || name == '..') {
      return "the skill name '$name' refers to the current or parent directory";
    }
    // Check both `/` and `\` on every platform: `p.split` treats `\` as text
    // on POSIX, where it is a legal file name character that Windows reads as
    // a path separator.
    if (name.contains('/') ||
        name.contains(r'\') ||
        p.isAbsolute(name) ||
        p.split(name).length != 1) {
      return "the skill name '$name' contains a path separator";
    }
    return null;
  }
}
