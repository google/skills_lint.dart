// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/reporters/reporters.dart';
import 'package:test/test.dart';

void main() {
  group('Reporter error prefix and attribution', () {
    const List<OutputFormat> formats = [OutputFormat.text, OutputFormat.json, OutputFormat.sarif];

    formats.forEach(_testFormatErrors);
  });
}

void _testFormatErrors(OutputFormat format) {
  group('for ${format.name} format', () {
    late StringBuffer outSink;
    late StringBuffer errSink;
    late Reporter reporter;

    setUp(() {
      outSink = StringBuffer();
      errSink = StringBuffer();
      reporter = Reporter.fromFormat(format, out: outSink, err: errSink);
    });

    test('onFixFailed includes prefix, attribution, blast radius on stderr and not stdout', () {
      reporter.onFixFailed(ruleName: 'trailing-whitespace', error: Exception('disk full'));

      final errOutput = errSink.toString();
      final outOutput = outSink.toString();

      expect(errOutput, contains(Reporter.toolErrorPrefix));
      expect(errOutput, contains("could not apply the 'trailing-whitespace' fix."));
      expect(errOutput, contains('This is a bug in skills_lint, not a problem with your skill.'));
      expect(errOutput, contains('Your skill was left unmodified. Cause: Exception: disk full'));

      if (format == OutputFormat.json || format == OutputFormat.sarif) {
        expect(outOutput, isEmpty);
      }
    });

    test('onRenameFailed includes prefix, attribution, blast radius on stderr and not stdout', () {
      reporter.onRenameFailed(
        oldSkillName: 'my-old-skill',
        targetSkillName: 'my-new-skill',
        error: Exception('permission denied'),
      );

      final errOutput = errSink.toString();
      final outOutput = outSink.toString();

      expect(errOutput, contains(Reporter.toolErrorPrefix));
      expect(
        errOutput,
        contains("could not rename skill directory from 'my-old-skill' to 'my-new-skill'."),
      );
      expect(errOutput, contains('This is a bug in skills_lint, not a problem with your skill.'));
      expect(
        errOutput,
        contains(
          "Your skill directory was left at 'my-old-skill'. Cause: Exception: permission denied",
        ),
      );

      if (format == OutputFormat.json || format == OutputFormat.sarif) {
        expect(outOutput, isEmpty);
      }
    });

    test(
      'onRenameTargetExists includes prefix, attribution, blast radius on stderr and not stdout',
      () {
        reporter.onRenameTargetExists(
          oldSkillName: 'my-old-skill',
          targetSkillName: 'my-new-skill',
          destinationPath: '/path/to/my-new-skill',
        );

        final errOutput = errSink.toString();
        final outOutput = outSink.toString();

        expect(errOutput, contains(Reporter.toolErrorPrefix));
        expect(
          errOutput,
          contains(
            "cannot rename skill directory from 'my-old-skill' to 'my-new-skill': "
            "destination directory '/path/to/my-new-skill' already exists.",
          ),
        );
        expect(errOutput, contains('This is a bug in skills_lint, not a problem with your skill.'));
        expect(errOutput, contains("Your skill directory was left at 'my-old-skill'."));

        if (format == OutputFormat.json || format == OutputFormat.sarif) {
          expect(outOutput, isEmpty);
        }
      },
    );

    test(
      'onBaselineFailed includes prefix, attribution, blast radius on stderr and not stdout',
      () {
        reporter.onBaselineFailed('/path/to/baseline.json', Exception('read-only filesystem'));

        final errOutput = errSink.toString();
        final outOutput = outSink.toString();

        expect(errOutput, contains(Reporter.toolErrorPrefix));
        expect(
          errOutput,
          contains("failed to generate baseline file at '/path/to/baseline.json'."),
        );
        expect(errOutput, contains('This is a bug in skills_lint, not a problem with your skill.'));
        expect(
          errOutput,
          contains(
            'Your baseline file was left unmodified. Cause: Exception: read-only filesystem',
          ),
        );

        if (format == OutputFormat.json || format == OutputFormat.sarif) {
          expect(outOutput, isEmpty);
        }
      },
    );
  });
}
