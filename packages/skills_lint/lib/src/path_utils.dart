// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:path/path.dart' as p;

/// Expands tilde (`~/`) at the start of a path to the user's home directory.
///
/// If the path does not start with `~/` or if the home directory cannot be
/// determined from the environment, the original path is returned.
String expandPath(String path) {
  if (path.startsWith('~/')) {
    final String? homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDir != null) {
      return p.join(homeDir, path.substring(2));
    }
  }
  return path;
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
