// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests of what [TextReporter] prints during `--fix`.
library;

import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/skipped_fix.dart';
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

  test('prints the errors that remain after fixes', () {
    final out = StringBuffer();
    final err = StringBuffer();
    TextReporter(out: out, err: err).onFixedSkillValidationComplete(invalidResult);

    expect(err.toString(), contains(TextReporter.skillIsInvalidMsg));
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

  group('onFixSkipped names the reason', () {
    String skippedLine(SkippedFix skipped) {
      final out = StringBuffer();
      TextReporter(out: out, err: StringBuffer()).onFixSkipped('my-skill', skipped);
      return out.toString().trim();
    }

    test('when the directory to rename to exists', () {
      expect(
        skippedLine(
          SkippedFix(ruleName: 'r', grownRuleNames: const ['g'], blockedDirectoryName: 'bar-foo'),
        ),
        allOf(startsWith('Skipped the r fix'), contains('bar-foo already exists')),
      );
    });

    test('when the fix adds diagnostics', () {
      expect(
        skippedLine(SkippedFix(ruleName: 'r', grownRuleNames: const ['g', 'h'])),
        allOf(startsWith('Skipped the r fix'), contains('add g, h diagnostics')),
      );
    });

    test('when the fix only fails to lower the count', () {
      expect(
        skippedLine(SkippedFix(ruleName: 'r', grownRuleNames: const [])),
        allOf(startsWith('Skipped the r fix'), contains('would not lower')),
      );
    });
  });
}
