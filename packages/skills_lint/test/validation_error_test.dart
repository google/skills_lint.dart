// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('ValidationError serialization and properties', () {
    test('positive round-trip with full properties', () {
      final full = ValidationError(
        ruleId: 'valid-yaml-metadata',
        file: 'SKILL.md',
        message: 'Invalid frontmatter syntax',
        severity: AnalysisSeverity.error,
        isIgnored: true,
        region: const SourceRegion(startLine: 2, startColumn: 1, endLine: 2, endColumn: 15),
        markdownMessage: '**Invalid YAML frontmatter.**\n\nSyntax error on line 2.',
      );

      expectJsonRoundTrip<ValidationError>(
        instance: full,
        toJson: (e) => e.toJson(),
        fromJson: ValidationError.fromJson,
      );
    });

    test('positive round-trip with minimal properties', () {
      final minimal = ValidationError(
        ruleId: 'check-relative-paths',
        file: 'SKILL.md',
        message: 'Missing reference file',
        severity: AnalysisSeverity.warning,
      );

      expectJsonRoundTrip<ValidationError>(
        instance: minimal,
        toJson: (e) => e.toJson(),
        fromJson: ValidationError.fromJson,
      );
    });

    test('negative handling on malformed JSON', () {
      expect(
        () => ValidationError.fromJson(const {
          'ruleId': 'r1',
          'file': 'f1',
          'message': 'm1',
          'severity': 'unknown_severity_name',
        }),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => ValidationError.fromJson(const {}), throwsA(isA<TypeError>()));
    });
  });
}
