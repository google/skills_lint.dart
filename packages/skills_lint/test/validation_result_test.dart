// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('ValidationResult serialization and properties', () {
    test('positive round-trip without context', () {
      final error = ValidationError(
        ruleId: 'r1',
        file: 'SKILL.md',
        message: 'Error message',
        severity: AnalysisSeverity.error,
      );
      final warning = ValidationError(
        ruleId: 'r2',
        file: 'SKILL.md',
        message: 'Warning message',
        severity: AnalysisSeverity.warning,
      );
      final result = ValidationResult(
        validationErrors: [error, warning],
        warnings: const ['Manual warning string'],
      );

      expectJsonRoundTrip<ValidationResult>(
        instance: result,
        toJson: (r) => r.toJson(),
        fromJson: ValidationResult.fromJson,
      );
    });

    test('negative handling on malformed JSON', () {
      expect(
        () => ValidationResult.fromJson(const {
          'validationErrors': ['not_a_map'],
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
