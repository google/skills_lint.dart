// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'models/ignore_entry.dart';
import 'models/skills_ignores.dart';

/// The result of [SkillsIgnoresStorage.load].
///
/// `ignores` holds every well-formed entry. `problems` describes each part of
/// the file that could not be read, one message per malformed entry. When
/// `problems` is not empty, `ignores` is missing those entries, so writing it
/// back to the file would delete them.
typedef IgnoresLoad = ({SkillsIgnores ignores, List<IgnoreProblem> problems});

/// A part of an ignore file that [SkillsIgnoresStorage.load] could not read.
///
/// `skill` names the skill whose entry is malformed, or is `null` when the
/// whole file could not be read. `message` names the file and describes the
/// problem.
typedef IgnoreProblem = ({String? skill, String message});

/// Service class for reading and writing the `SkillsIgnores` model to/from disk.
class SkillsIgnoresStorage {
  /// Loads the [SkillsIgnores] at [path], with a description of each part of
  /// the file that could not be read.
  ///
  /// Returns empty ignores and no problems if the file does not exist, is
  /// empty, or holds only whitespace. Reads
  /// the file entry by entry: a malformed entry is left out and described in
  /// `problems`, and the other entries still load. A file that
  /// can't be read, isn't JSON, or whose top level has the wrong shape loads
  /// as empty ignores with one problem.
  Future<IgnoresLoad> load(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return (ignores: SkillsIgnores(skills: {}), problems: <IgnoreProblem>[]);
    }

    final Object? json;
    try {
      final String content = await file.readAsString();
      if (content.trim().isEmpty) {
        return (ignores: SkillsIgnores(skills: {}), problems: <IgnoreProblem>[]);
      }
      json = jsonDecode(content);
    } on FileSystemException catch (e) {
      // Unreadable file (permissions, invalid UTF-8).
      return _unreadable(path, 'could not be read: ${e.message}');
    } on FormatException catch (e) {
      return _unreadable(path, 'is not valid JSON: ${e.message}');
    }
    return _parse(path, json);
  }

  static IgnoresLoad _unreadable(String path, String reason) =>
      (ignores: SkillsIgnores(skills: {}), problems: [(skill: null, message: '$path $reason')]);

  static IgnoresLoad _parse(String path, Object? json) {
    if (json is! Map<String, dynamic>) {
      return _unreadable(path, 'must be a JSON object with a "${SkillsIgnores.skillsKey}" key.');
    }
    // `{}` has no entries. Any other object without a `skills` object, such
    // as one with a misspelled key, is a problem, so that
    // `--generate-baseline` does not overwrite it.
    if (json.isEmpty) {
      return (ignores: SkillsIgnores(skills: {}), problems: <IgnoreProblem>[]);
    }
    final Object? skillsJson = json[SkillsIgnores.skillsKey];
    if (skillsJson is! Map<String, dynamic>) {
      return _unreadable(
        path,
        'has a "${SkillsIgnores.skillsKey}" value that is not an object of skill names.',
      );
    }

    final skills = <String, List<IgnoreEntry>>{};
    final problems = <IgnoreProblem>[];
    for (final MapEntry<String, dynamic>(key: skillName, value: entriesJson)
        in skillsJson.entries) {
      if (entriesJson is! List<dynamic>) {
        problems.add((
          skill: skillName,
          message: '$path: skill "$skillName" must list its entries in a JSON array.',
        ));
        continue;
      }
      final entries = <IgnoreEntry>[];
      for (var i = 0; i < entriesJson.length; i++) {
        final Object? entryJson = entriesJson[i];
        final String? problem = entryJson is Map<String, dynamic>
            ? _entryProblem(entryJson)
            : 'must be a JSON object.';
        if (problem != null) {
          problems.add((
            skill: skillName,
            message: '$path: skill "$skillName", entry ${i + 1}: $problem',
          ));
          continue;
        }
        try {
          entries.add(IgnoreEntry.fromJson(entryJson! as Map<String, dynamic>));
        } on TypeError catch (e) {
          // The generated fromJson checks shape through `as` casts. This
          // catches a field it requires that _entryProblem does not check.
          problems.add((
            skill: skillName,
            message: '$path: skill "$skillName", entry ${i + 1}: $e',
          ));
        }
      }
      skills[skillName] = entries;
    }
    return (ignores: SkillsIgnores(skills: skills), problems: problems);
  }

  /// Describes what is wrong with [entryJson], or returns `null` if it is a
  /// well-formed ignore entry.
  static String? _entryProblem(Map<String, dynamic> entryJson) {
    final List<String> problems = [
      for (final key in [IgnoreEntry.ruleIdKey, IgnoreEntry.fileNameKey])
        if (!entryJson.containsKey(key))
          'missing "$key"'
        else if (entryJson[key] is! String)
          '"$key" must be a string',
      if (entryJson[IgnoreEntry.subjectKey] case final Object subject when subject is! String)
        '"${IgnoreEntry.subjectKey}" must be a string',
    ];
    return problems.isEmpty ? null : '${problems.join('; ')}.';
  }

  /// Saves `SkillsIgnores` to the specified path.
  Future<void> save(String path, SkillsIgnores ignores) async {
    final file = File(path);
    final String jsonString = const JsonEncoder.withIndent('  ').convert(ignores.toJson());
    await file.writeAsString(jsonString);
  }
}
