// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';

import 'validation_error.dart';

part 'ignore_entry.g.dart';

/// Represents a single ignored rule entry for a specific file.
@JsonSerializable()
class IgnoreEntry {
  IgnoreEntry({required this.ruleId, required this.fileName, this.target, this.used = false});

  /// Creates an IgnoreEntry from a JSON map.
  factory IgnoreEntry.fromJson(Map<String, dynamic> json) => _$IgnoreEntryFromJson(json);

  static const String ruleIdKey = 'rule_id';
  static const String fileNameKey = 'file_name';
  static const String targetKey = 'target';

  /// The rule ID that should be suppressed (e.g., 'description_too_long').
  @JsonKey(name: ruleIdKey)
  final String ruleId;

  /// The file name to apply this suppression to.
  @JsonKey(name: fileNameKey)
  final String fileName;

  /// Specific finding target within [fileName] (such as a link path) to
  /// restrict this suppression to.
  ///
  /// For link rules, [target] is the raw link destination as written in
  /// `SKILL.md`, with any `#anchor` or `%`-escapes preserved and any link
  /// title stripped.
  ///
  /// When `null`, the entry acts as a wildcard for `(ruleId, fileName)` and
  /// suppresses every finding of [ruleId] in [fileName], regardless of whether
  /// [ValidationError.target] is set.
  ///
  /// When non-null, the entry matches only a [ValidationError] with the same
  /// [ruleId], [fileName], and an equal [ValidationError.target]. If a rule
  /// does not populate [ValidationError.target], an entry with a non-null
  /// [target] for that rule never matches and is reported as a stale ignore.
  ///
  /// If a skill lists both a whole-file entry (`target == null`) and a
  /// targeted entry (`target != null`) for the same rule and file, the first
  /// matching entry in the list marks the finding ignored and marks itself
  /// [used]. Any later entry that never matches a remaining un-ignored
  /// finding stays unused and is reported as stale.
  ///
  /// Values must identify the offending construct itself rather than a line
  /// number, because baseline entries persist across edits and a line number
  /// would go stale whenever lines above the finding are added or removed.
  @JsonKey(name: targetKey, includeIfNull: false)
  final String? target;

  /// Whether this entry has been used during the run.
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool used;

  /// Converts an IgnoreEntry to a JSON map.
  Map<String, dynamic> toJson() => _$IgnoreEntryToJson(this);
}
