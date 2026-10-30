// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

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

    group("reports problems in the user's files without calling them a tool bug", () {
      void expectUserFacing(String errOutput) {
        expect(errOutput, startsWith('${Reporter.userErrorPrefix} '));
        expect(errOutput, isNot(contains(Reporter.toolErrorPrefix)));
        expect(errOutput, isNot(contains('bug in skills_lint')));
        if (format == OutputFormat.json || format == OutputFormat.sarif) {
          expect(outSink.toString(), isEmpty);
        }
      }

      test('onRenameBlocked names both directories and the reason', () {
        reporter.onRenameBlocked(
          oldSkillName: 'my-old-skill',
          targetSkillName: 'my-new-skill',
          reason: 'directory my-new-skill already exists',
        );

        final errOutput = errSink.toString();
        expectUserFacing(errOutput);
        expect(
          errOutput,
          contains(
            "could not rename skill directory 'my-old-skill' to 'my-new-skill': "
            'directory my-new-skill already exists.',
          ),
        );
        expect(errOutput, contains("left at 'my-old-skill'"));
      });

      test('onWriteFailed names the file and the OS error', () {
        reporter.onWriteFailed(
          skillMdPath: '/skills/my-skill/SKILL.md',
          error: const FileSystemException(
            'Cannot open file',
            '/skills/my-skill/SKILL.md',
            OSError('Permission denied', 13),
          ),
        );

        final errOutput = errSink.toString();
        expectUserFacing(errOutput);
        expect(
          errOutput,
          contains("could not write '/skills/my-skill/SKILL.md': Permission denied"),
        );
        expect(errOutput, contains('left unchanged'));
      });

      test('onRenamedButNotWritten says the skill was renamed but not written', () {
        reporter.onRenamedButNotWritten(
          fromPath: '/skills/foo',
          toPath: '/skills/bar-foo',
          writeError: const FileSystemException(
            'Cannot open file',
            '',
            OSError('Permission denied'),
          ),
          undoError: const FileSystemException(
            'Rename failed',
            '',
            OSError('Read-only file system'),
          ),
        );

        final errOutput = errSink.toString();
        expectUserFacing(errOutput);
        expect(errOutput, contains("renamed '/skills/foo' to '/skills/bar-foo'"));
        expect(errOutput, contains('but SKILL.md was not written'));
        expect(errOutput, contains('Permission denied'));
        expect(errOutput, contains('Read-only file system'));
      });
    });

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
