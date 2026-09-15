// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'analysis_severity.dart';
import 'source_region.dart';

/// Represents a single validation error found during analysis.
class ValidationError {
  ValidationError({
    required this.ruleId,
    required this.file,
    required this.message,
    required this.severity,
    this.isIgnored = false,
    this.region,
  });

  /// Constructs a [ValidationError] from a JSON map.
  factory ValidationError.fromJson(Map<String, Object?> json) => ValidationError(
    ruleId: json[keyRuleId]! as String,
    file: json[keyFile]! as String,
    message: json[keyMessage]! as String,
    severity: AnalysisSeverity.values.byName(json[keySeverity]! as String),
    isIgnored: json[keyIsIgnored] as bool? ?? false,
    region: json[keyRegion] != null
        ? SourceRegion.fromJson(json[keyRegion]! as Map<String, Object?>)
        : null,
  );

  /// JSON key for [ruleId].
  static const String keyRuleId = 'ruleId';

  /// JSON key for [file].
  static const String keyFile = 'file';

  /// JSON key for [message].
  static const String keyMessage = 'message';

  /// JSON key for [severity].
  static const String keySeverity = 'severity';

  /// JSON key for [isIgnored].
  static const String keyIsIgnored = 'isIgnored';

  /// JSON key for [region].
  static const String keyRegion = 'region';

  /// The unique rule ID (e.g., 'description_too_long').
  final String ruleId;

  /// The file name context (e.g., 'SKILL.md' or relative path).
  final String file;

  /// The human-readable error message.
  final String message;

  /// The severity of the error.
  final AnalysisSeverity severity;

  /// Whether this error has been ignored via configuration.
  bool isIgnored;

  /// Precise 1-based source location coordinates, if available.
  final SourceRegion? region;

  /// Converts this error to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    keyRuleId: ruleId,
    keyFile: file,
    keyMessage: message,
    keySeverity: severity.name,
    keyIsIgnored: isIgnored,
    if (region != null) keyRegion: region!.toJson(),
  };
}
