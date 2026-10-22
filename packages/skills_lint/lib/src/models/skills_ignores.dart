// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';
import 'ignore_entry.dart';

part 'skills_ignores.g.dart';

/// Represents the top-level structure of the skills ignore JSON file.
@JsonSerializable(explicitToJson: true)
class SkillsIgnores {
  SkillsIgnores({required this.skills});

  /// Creates a SkillsIgnores from a JSON map.
  factory SkillsIgnores.fromJson(Map<String, dynamic> json) => _$SkillsIgnoresFromJson(json);

  static const String skillsKey = 'skills';

  /// Map of skill names to their list of ignore entries.
  @JsonKey(name: skillsKey)
  final Map<String, List<IgnoreEntry>> skills;

  /// Moves any ignore entries stored under [oldSkillName] to [newSkillName].
  ///
  /// Returns `true` if [oldSkillName] had entries and was moved.
  bool renameSkill(String oldSkillName, String newSkillName) {
    if (oldSkillName == newSkillName) {
      return false;
    }
    final List<IgnoreEntry>? moved = skills.remove(oldSkillName);
    if (moved == null) {
      return false;
    }
    final List<IgnoreEntry>? existing = skills[newSkillName];
    if (existing == null) {
      skills[newSkillName] = moved;
      return true;
    }
    final seen = <String>{
      for (final IgnoreEntry entry in existing) '${entry.ruleId}:${entry.fileName}',
    };
    for (final IgnoreEntry entry in moved) {
      if (seen.add('${entry.ruleId}:${entry.fileName}')) {
        existing.add(entry);
      }
    }
    return true;
  }

  /// Converts a SkillsIgnores to a JSON map.
  Map<String, dynamic> toJson() => _$SkillsIgnoresToJson(this);
}
