// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import 'analysis_severity.dart';
import 'skill_context.dart';
import 'validation_error.dart';

/// The result of a skill directory validation attempt.
class ValidationResult {
  ValidationResult({
    this.validationErrors = const [],
    List<String> warnings = const [],
    this.context,
  }) : _manualWarnings = warnings;

  /// Constructs a [ValidationResult] from a JSON map.
  factory ValidationResult.fromJson(Map<String, Object?> json) {
    final List<ValidationError> errors =
        (json[keyValidationErrors] as List<Object?>?)
            ?.map((e) => ValidationError.fromJson(e! as Map<String, Object?>))
            .toList() ??
        [];
    final List<String> manualWarnings =
        (json[keyWarnings] as List<Object?>?)
            ?.map((e) => e.toString())
            .where(
              (w) => !errors.any((e) => e.severity == AnalysisSeverity.warning && e.message == w),
            )
            .toList() ??
        [];
    return ValidationResult(validationErrors: errors, warnings: manualWarnings);
  }

  /// JSON key for [skillName].
  static const String keySkillName = 'skillName';

  /// JSON key for [skillPath].
  static const String keySkillPath = 'skillPath';

  /// JSON key for [isValid].
  static const String keyIsValid = 'isValid';

  /// JSON key for [errors].
  static const String keyErrors = 'errors';

  /// JSON key for [warnings].
  static const String keyWarnings = 'warnings';

  /// JSON key for [validationErrors].
  static const String keyValidationErrors = 'validationErrors';

  /// The context used during validation.
  final SkillContext? context;

  /// Whether the skill directory is valid according to the specification.
  bool get isValid =>
      !validationErrors.any((e) => e.severity == AnalysisSeverity.error && !e.isIgnored);

  /// A list of structured validation errors found.
  final List<ValidationError> validationErrors;

  final List<String> _manualWarnings;

  /// A list of error messages for failing checks (excluding ignored ones).
  List<String> get errors => validationErrors
      .where((e) => e.severity == AnalysisSeverity.error && !e.isIgnored)
      .map((e) => e.message)
      .toList();

  /// A list of warning messages for suboptimal setups or recommendations.
  List<String> get warnings => [
    ..._manualWarnings,
    ...validationErrors
        .where((e) => e.severity == AnalysisSeverity.warning && !e.isIgnored)
        .map((e) => e.message),
  ];

  /// Converts this result to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    if (context != null) ...{
      keySkillName: p.basename(context!.directory.path),
      keySkillPath: context!.directory.path,
    },
    keyIsValid: isValid,
    keyErrors: errors,
    keyWarnings: warnings,
    keyValidationErrors: validationErrors.map((e) => e.toJson()).toList(),
  };
}
