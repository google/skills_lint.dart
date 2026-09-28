// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'models/skills_ignores.dart';

/// Service class for reading and writing the `SkillsIgnores` model to/from disk.
class SkillsIgnoresStorage {
  /// Loads `SkillsIgnores` from the specified path.
  ///
  /// Returns an empty `SkillsIgnores` if the file does not exist or fails to parse.
  Future<SkillsIgnores> load(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return SkillsIgnores(skills: {});
    }

    try {
      final String content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return SkillsIgnores.fromJson(json);
    } on FileSystemException {
      // Unreadable file (permissions, invalid UTF-8).
      return SkillsIgnores(skills: {});
    } on FormatException {
      // Not valid JSON.
      return SkillsIgnores(skills: {});
    } on TypeError {
      // Valid JSON of the wrong shape, including `{}` with no `skills` key.
      // The generated _$SkillsIgnoresFromJson checks shape only through `as`
      // casts, so a TypeError is how it reports a malformed document.
      return SkillsIgnores(skills: {});
    }
  }

  /// Saves `SkillsIgnores` to the specified path.
  Future<void> save(String path, SkillsIgnores ignores) async {
    final file = File(path);
    final String jsonString = const JsonEncoder.withIndent('  ').convert(ignores.toJson());
    await file.writeAsString(jsonString);
  }
}
