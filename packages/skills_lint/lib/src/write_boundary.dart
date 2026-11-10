// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'path_utils.dart';

/// The directory that skills_lint may write in for one scan target.
///
/// The files under a scan target choose paths that `--fix`,
/// `--generate-baseline` and ignore-file creation write to: directory names,
/// frontmatter `name` values, symlinks, and the target's `skills_lint.yaml`.
/// Every such write and rename is checked here, after symlinks are resolved,
/// so that content in a scanned repository can't reach files outside it.
@immutable
final class WriteBoundary {
  /// A boundary at the absolute path [directory].
  const WriteBoundary(String this.directory);

  /// No boundary, for a path the user named on the command line or through
  /// the API.
  const WriteBoundary.none() : directory = null;

  /// The boundary for the skills directory at the absolute path [directory]:
  /// [directory] itself.
  ///
  /// See [WriteBoundary._confined] for [configDirectory].
  factory WriteBoundary.forSkillsDirectory(String directory, {String? configDirectory}) =>
      _confined(directory, boundary: directory, configDirectory: configDirectory);

  /// The boundary for the individual skill at the absolute path [skill]: the
  /// directory that holds the skill after symlinks are resolved, so that
  /// `--fix` can rename the skill next to where it is.
  ///
  /// See [WriteBoundary._confined] for [configDirectory].
  factory WriteBoundary.forSkill(String skill, {String? configDirectory}) =>
      _confined(skill, boundary: p.dirname(resolve(skill)), configDirectory: configDirectory);

  /// A [WriteBoundary] at [boundary] for a scan target at [target].
  ///
  /// A target declared in a configuration file must also be inside
  /// [configDirectory], the directory the file's paths are relative to. When
  /// it isn't, the boundary is [configDirectory], so every write in the
  /// target is refused.
  static WriteBoundary _confined(
    String target, {
    required String boundary,
    required String? configDirectory,
  }) {
    if (configDirectory == null || isAtOrWithin(resolve(configDirectory), resolve(target))) {
      return WriteBoundary(boundary);
    }
    return WriteBoundary(configDirectory);
  }

  /// The absolute directory that writes must stay inside, or `null` for no
  /// boundary.
  final String? directory;

  /// What a user does to write outside a boundary on purpose.
  static const String hint =
      'skills_lint writes only inside the directories it scans. '
      'To write there anyway, name the path with -s, -d or --ignore-file.';

  /// Why writing or creating [path] is refused, readable as the end of a
  /// sentence, or `null` when [path] is inside the boundary.
  String? refusal(String path) {
    final String? root = directory;
    if (root == null) {
      return null;
    }
    final String realRoot = resolve(root);
    final String realPath = resolve(path);
    if (p.isWithin(realRoot, realPath)) {
      return null;
    }
    if (p.equals(realPath, p.normalize(path))) {
      return "it is outside '$realRoot'";
    }
    return "it resolves to '$realPath', outside '$realRoot'";
  }

  /// Whether [name] can be used as a directory name next to another one:
  /// a single path segment that is not `.` or `..`.
  static bool isSingleSegment(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !p.isAbsolute(name) &&
      p.split(name).length == 1 &&
      !name.contains('/') &&
      !name.contains(r'\');

  /// The longest chain of symlinks [resolve] follows.
  ///
  /// Matches the usual operating system limit, so a loop of links ends.
  static const int _maxLinks = 40;

  /// The real location of the absolute path [path], with every symlink in it
  /// resolved, including a dangling one at the end.
  ///
  /// [path] or its last segments may not exist yet, such as a rename target
  /// or an ignore file that is about to be created. Those segments are kept
  /// as they are, after the deepest part that exists has been resolved.
  @visibleForTesting
  static String resolve(String path) => _resolve(p.normalize(path), linksLeft: _maxLinks);

  static String _resolve(String path, {required int linksLeft}) {
    var existing = path;
    final missing = <String>[];
    while (FileSystemEntity.typeSync(existing, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final String parent = p.dirname(existing);
      if (parent == existing) {
        return path;
      }
      missing.insert(0, p.basename(existing));
      existing = parent;
    }
    if (FileSystemEntity.isLinkSync(existing)) {
      if (linksLeft == 0) {
        throw FileSystemException('Too many levels of symbolic links', path);
      }
      // Follow the link by hand: resolveSymbolicLinksSync fails on a dangling
      // link, and writing through one creates its target.
      final String target = Link(existing).targetSync();
      final String parent = _resolve(p.dirname(existing), linksLeft: linksLeft - 1);
      return _resolve(
        p.normalize(p.joinAll([p.join(parent, target), ...missing])),
        linksLeft: linksLeft - 1,
      );
    }
    final String real = Directory(existing).resolveSymbolicLinksSync();
    return p.joinAll([real, ...missing]);
  }
}
