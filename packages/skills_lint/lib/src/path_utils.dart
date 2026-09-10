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
/// ## Boundary Canonicalization Architecture
///
/// In `skills_lint`, path canonicalization is performed eagerly at the boundaries:
/// 1. **Configuration Boundary (`ConfigParser`)**: Target paths (`directories`,
///    `individual_skills`) and `ignore_file` paths defined in YAML configuration files
///    are canonicalized immediately relative to the configuration file's parent directory.
/// 2. **CLI / API Boundary (`entry_point.dart`)**: Target paths and ignore files passed via
///    command-line flags or top-level API calls are canonicalized immediately relative to
///    `Directory.current.path`.
///
/// Once paths cross these boundaries into the execution core ([ValidationSession]),
/// all paths are guaranteed to be normalized, absolute canonical paths, preventing
/// path drift and fragile relative-path comparisons.
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
