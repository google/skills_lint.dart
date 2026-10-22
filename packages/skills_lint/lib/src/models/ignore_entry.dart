// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';

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
  /// When `null`, the entry suppresses every finding of [ruleId] in
  /// [fileName].
  @JsonKey(name: targetKey, includeIfNull: false)
  final String? target;

  /// Whether this entry has been used during the run.
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool used;

  /// Converts an IgnoreEntry to a JSON map.
  Map<String, dynamic> toJson() => _$IgnoreEntryToJson(this);
}
