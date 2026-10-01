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
