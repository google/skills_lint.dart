// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:path/path.dart' as p;

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
/// ## Boundary canonicalization architecture
///
/// Paths are canonicalized eagerly, at the boundary where they enter the tool:
/// 1. **Configuration boundary (`ConfigParser`)**: target paths (`directories`,
///    `individual_skills`) and `ignore_file` paths declared in a YAML
///    configuration file are anchored to that file's parent directory.
/// 2. **CLI and API boundary (`validateSkillsInternal`)**: target paths and
///    ignore files supplied by command-line flags or by programmatic callers
///    are anchored to [Directory.current].
/// 3. **Session boundary (`ValidationSession`)**: paths handed to the session's
///    public methods are anchored through a single private helper.
///
/// Code behind those boundaries operates on absolute, normalized paths and must
/// not canonicalize again. `test/path_boundary_test.dart` enumerates the
/// boundaries and fails when a call site is added anywhere else, so a rule or
/// feature added later inherits the guarantee instead of re-implementing it.
///
/// ## Steps performed:
/// 1. Expands tildes (`~`, `~/`, `~\`) to the user's home directory.
/// 2. If the path is absolute, normalizes and returns it.
/// 3. If the path is relative, joins it to [baseDirectory] and normalizes it.
String canonicalizePath(String rawPath, {required String baseDirectory}) {
  final String expanded = expandPath(rawPath);
  if (p.isAbsolute(expanded)) {
    return p.normalize(expanded);
  }
  return p.normalize(p.join(baseDirectory, expanded));
}

/// Canonicalizes every entry of [rawPaths] against [baseDirectory].
///
/// Follows the contract documented on [canonicalizePath].
List<String> canonicalizePaths(Iterable<String> rawPaths, {required String baseDirectory}) {
  return <String>[
    for (final String rawPath in rawPaths) canonicalizePath(rawPath, baseDirectory: baseDirectory),
  ];
}

/// Canonicalizes [rawPath] against [baseDirectory], passing `null` through.
///
/// An empty [rawPath] also resolves to `null`, so an unset option and a blank
/// option behave identically. Follows the contract documented on
/// [canonicalizePath].
String? canonicalizePathOrNull(String? rawPath, {required String baseDirectory}) {
  if (rawPath == null || rawPath.isEmpty) {
    return null;
  }
  return canonicalizePath(rawPath, baseDirectory: baseDirectory);
}

/// Expresses [path] relative to [relativeTo], the inverse of
/// [canonicalizePath].
///
/// Canonicalization anchors a path where it enters the tool. Writing a
/// configuration back out reverses that step, so a file that declared
/// `path: skills` keeps declaring `path: skills` instead of gaining an absolute
/// path that only resolves on the machine that wrote it.
///
/// A path outside [relativeTo] is expressed with leading `..` segments rather
/// than kept absolute. A configuration in a subpackage that targets a skills
/// directory or an ignore file higher in the repository declares exactly such a
/// path, and that form is portable while the two keep their positions.
///
/// [path] is returned unchanged when:
/// * [relativeTo] is `null`,
/// * [path] is relative, so no anchor was applied to reverse,
/// * [path] and [relativeTo] have different roots, which have no relative form.
String relativizePath(String path, {required String? relativeTo}) {
  if (relativeTo == null || !p.isAbsolute(path)) {
    return path;
  }
  if (p.equals(relativeTo, path)) {
    return '.';
  }
  if (!p.equals(p.rootPrefix(relativeTo), p.rootPrefix(path))) {
    return path;
  }
  return p.relative(path, from: relativeTo);
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
