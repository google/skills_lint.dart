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
  /// A boundary at the absolute path [directory], widened to the absolute
  /// directories in [allowed].
  const WriteBoundary(String this.directory, {this.allowed = const []});

  /// No boundary, for a path the user named on the command line or through
  /// the API.
  const WriteBoundary.none() : directory = null, allowed = const [];

  /// The boundary for the skills directory at the absolute path [directory]:
  /// [directory] itself.
  ///
  /// [allowed] holds directories from `--allow-write`, and [configAllowed]
  /// those from the target's `write_allow`. See [WriteBoundary._confined] for
  /// [configDirectory].
  factory WriteBoundary.forSkillsDirectory(
    String directory, {
    String? configDirectory,
    List<String> configAllowed = const [],
    List<String> allowed = const [],
  }) => _confined(
    directory,
    boundary: directory,
    configDirectory: configDirectory,
    allowed: [...allowed, ..._inside(configDirectory, configAllowed)],
  );

  /// The boundary for the individual skill at the absolute path [skill]: the
  /// directory that holds the skill after symlinks are resolved, so that
  /// `--fix` can rename the skill next to where it is.
  ///
  /// See [WriteBoundary.forSkillsDirectory] for the other parameters.
  factory WriteBoundary.forSkill(
    String skill, {
    String? configDirectory,
    List<String> configAllowed = const [],
    List<String> allowed = const [],
  }) => _confined(
    skill,
    boundary: p.dirname(resolve(skill)),
    configDirectory: configDirectory,
    allowed: [...allowed, ..._inside(configDirectory, configAllowed)],
  );

  /// The directories in [configAllowed] that are inside [configDirectory]
  /// after symlinks are resolved.
  ///
  /// The parser already requires each to be inside as written. This drops one
  /// that a symlink leads elsewhere, so `write_allow` in a configuration file
  /// can't reach outside the file's directory.
  static List<String> _inside(String? configDirectory, List<String> configAllowed) {
    final List<String> escaping = escapingConfigDirectory(configDirectory, configAllowed);
    return [
      for (final String directory in configAllowed)
        if (!escaping.contains(directory)) directory,
    ];
  }

  /// The directories in [configAllowed] that a symlink leads outside
  /// [configDirectory], which no boundary includes.
  static List<String> escapingConfigDirectory(String? configDirectory, List<String> configAllowed) {
    if (configDirectory == null) {
      return const [];
    }
    final String realConfigDirectory = resolve(configDirectory);
    return [
      for (final String directory in configAllowed)
        if (!isAtOrWithin(realConfigDirectory, resolve(directory))) directory,
    ];
  }

  /// A [WriteBoundary] at [boundary], widened to [allowed], for a scan target
  /// at [target].
  ///
  /// A target declared in a configuration file must also be inside
  /// [configDirectory], the directory the file's paths are relative to. When
  /// it isn't, the boundary is [configDirectory], so every write in the
  /// target is refused.
  static WriteBoundary _confined(
    String target, {
    required String boundary,
    required String? configDirectory,
    required List<String> allowed,
  }) {
    if (configDirectory == null || isAtOrWithin(resolve(configDirectory), resolve(target))) {
      return WriteBoundary(boundary, allowed: allowed);
    }
    return WriteBoundary(configDirectory, allowed: allowed);
  }

  /// The absolute directory that writes must stay inside, or `null` for no
  /// boundary.
  final String? directory;

  /// Absolute directories outside [directory] that writes may also land in,
  /// from `write_allow` and `--allow-write`.
  final List<String> allowed;

  /// What a user does to write outside a boundary on purpose.
  static const String hint =
      'skills_lint writes only inside the directories it scans. To write to that '
      'path anyway, name it with -s, -d or --ignore-file, or pass --allow-write <dir>. '
      'write_allow in skills_lint.yaml also works for directories next to that file.';

  /// Why writing or creating [path] is refused, readable as the end of a
  /// sentence, or `null` when [path] is inside the boundary.
  String? refusal(String path) {
    final String? root = directory;
    if (root == null) {
      return null;
    }
    final String realRoot = resolve(root);
    final String realPath = resolve(path);
    if (p.isWithin(realRoot, realPath) ||
        allowed.any((String directory) => isAtOrWithin(resolve(directory), realPath))) {
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
      // p.split treats `\` as text on POSIX, where it is a legal file name
      // character that Windows reads as a separator.
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
  /// as they are. Each segment is resolved before the `..` after it applies,
  /// as the operating system does.
  @visibleForTesting
  static String resolve(String path) {
    int linksLeft = _maxLinks;
    String walk(String path) {
      final List<String> segments = p.split(path);
      // Every prefix of `real` is resolved, so `..` can drop its last segment
      // as text.
      String real = segments.first;
      for (final String segment in segments.skip(1)) {
        if (segment == '.') {
          continue;
        }
        if (segment == '..') {
          real = p.dirname(real);
          continue;
        }
        final String next = p.join(real, segment);
        if (FileSystemEntity.typeSync(next, followLinks: false) != FileSystemEntityType.link) {
          real = next;
          continue;
        }
        if (--linksLeft < 0) {
          throw FileSystemException('Too many levels of symbolic links', path);
        }
        // Follow the link by hand: resolveSymbolicLinksSync fails on a
        // dangling link, and writing through one creates its target.
        real = walk(p.join(real, Link(next).targetSync()));
      }
      return real;
    }

    return walk(p.absolute(path));
  }
}
