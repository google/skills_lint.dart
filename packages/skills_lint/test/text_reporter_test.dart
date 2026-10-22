// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests of what [TextReporter] prints for the result after `--fix`, which
/// decides the exit code and so must be visible.
library;

import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/models/validation_result.dart';
import 'package:skills_lint/src/reporters/text_reporter.dart';
import 'package:test/test.dart';

void main() {
  final invalidResult = ValidationResult(
    validationErrors: [
      ValidationError(
        ruleId: 'some-rule',
        message: 'Still broken',
        severity: AnalysisSeverity.error,
        file: 'SKILL.md',
      ),
    ],
  );

  test('prints the heading and the remaining errors after fixes', () {
    final out = StringBuffer();
    final err = StringBuffer();
    TextReporter(out: out, err: err).onFixedSkillValidationComplete(invalidResult);

    expect(out.toString(), contains(TextReporter.afterFixesMsg));
    expect(err.toString(), contains('Still broken'));
  });

  test('with --quiet, prints nothing for a skill the fixes made valid', () {
    final out = StringBuffer();
    final err = StringBuffer();
    TextReporter(
      out: out,
      err: err,
      quiet: true,
    ).onFixedSkillValidationComplete(ValidationResult());

    expect(out.toString(), isEmpty);
    expect(err.toString(), isEmpty);
  });

  test('with --quiet, still prints the heading before remaining errors', () {
    final out = StringBuffer();
    final err = StringBuffer();
    TextReporter(out: out, err: err, quiet: true).onFixedSkillValidationComplete(invalidResult);

    expect(out.toString(), contains(TextReporter.afterFixesMsg));
    expect(err.toString(), contains('Still broken'));
  });
}
