// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:path/path.dart' as p;

/// Whether the file or directory at path [candidate] is the directory at path
/// [parent], or sits somewhere under it.
///
/// `p.isWithin` answers `false` when the two paths are equal, so callers that
/// need the directory itself to count use this instead. The comparison is a
/// pure path operation: it does not resolve symlinks or touch the file system.
bool isAtOrWithin(String parent, String candidate) =>
    p.equals(parent, candidate) || p.isWithin(parent, candidate);

/// Expands tildes (`~/`, `~\`, or `~`) to the user's home directory.
///
/// If the path does not start with a tilde prefix, or if the home directory
/// cannot be determined from the environment, the original path is returned.
String expandPath(String path) {
  if (path == '~') {
    final String? homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDir != null) {
      return homeDir;
    }
  } else if (path.startsWith('~/') || path.startsWith(r'~\')) {
    final String? homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDir != null) {
      return p.join(homeDir, path.substring(2));
    }
  }
  return path;
}

/// Canonicalizes [rawPath] against [baseDirectory].
///
/// Expands a leading tilde, then returns an absolute, normalized path. An
/// absolute [rawPath] is normalized as it stands; a relative one is joined to
/// [baseDirectory] first.
///
/// Call this only where a path enters the tool, which happens in three places:
/// `ConfigParser` anchors configuration paths to the directory holding the
/// configuration file, `validateSkillsInternal` anchors CLI and API paths to
/// [Directory.current], and `ValidationSession` anchors paths handed to its
/// public methods. Code behind those points already holds absolute paths and
/// must not canonicalize again, so a rule or feature added later inherits the
/// guarantee. `test/path_boundary_test.dart` fails when a fourth call site
/// appears.
String canonicalizePath(String rawPath, {required String baseDirectory}) {
  final String expanded = expandPath(rawPath);
  if (p.isAbsolute(expanded)) {
    return p.normalize(expanded);
  }
  return p.normalize(p.join(baseDirectory, expanded));
}

/// Canonicalizes every entry of [rawPaths] against [baseDirectory] with
/// [canonicalizePath].
List<String> canonicalizePaths(Iterable<String> rawPaths, {required String baseDirectory}) {
  return <String>[
    for (final String rawPath in rawPaths) canonicalizePath(rawPath, baseDirectory: baseDirectory),
  ];
}

/// Canonicalizes [rawPath] against [baseDirectory] with [canonicalizePath],
/// passing `null` through.
///
/// An empty [rawPath] also resolves to `null`, so an unset option and a blank
/// option behave identically.
String? canonicalizePathOrNull(String? rawPath, {required String baseDirectory}) {
  if (rawPath == null || rawPath.isEmpty) {
    return null;
  }
  return canonicalizePath(rawPath, baseDirectory: baseDirectory);
}

/// Normalizes a skill name or suffix into a valid skill name token.
///
/// Replaces invalid characters and underscores with hyphens, deduplicates
/// consecutive hyphens, strips leading and trailing hyphens, and truncates
/// to [maxLength].
String normalizeSkillNameToken(String input, {int maxLength = 64}) {
  String s = input.toLowerCase();
  s = s.replaceAll(RegExp(r'[^a-z0-9\-]+'), '-');
  s = s.replaceAll(RegExp(r'-+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > maxLength) {
    s = s.substring(0, maxLength);
    s = s.replaceAll(RegExp(r'-+$'), '');
  }
  return s;
}

/// The longest chain of symlinks [resolveSymlinks] follows.
///
/// Matches the usual operating system limit, so a loop of links ends.
const int _maxSymlinks = 40;

/// The real location of the absolute path [path], with every symlink in it
/// resolved, including a dangling one at the end.
///
/// [path] or its last segments may not exist yet, such as a rename target
/// or an ignore file that is about to be created. Those segments are kept
/// as they are. Each segment is resolved before the `..` after it applies,
/// as the operating system does.
String resolveSymlinks(String path) {
  int linksLeft = _maxSymlinks;
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

/// Why [directory] is not at or inside [configDirectory] after symlinks are
/// resolved, readable as the end of a sentence, or `null` when it stays
/// inside.
String? configDirectoryEscapeReason(String configDirectory, String directory) {
  try {
    if (isAtOrWithin(resolveSymlinks(configDirectory), resolveSymlinks(directory))) {
      return null;
    }
    return 'a symlink leads outside the directory of the configuration file';
  } on FileSystemException catch (e) {
    return 'could not resolve symlinks (${e.osError?.message ?? e.message})';
  }
}
