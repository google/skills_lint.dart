// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math';

import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/source_region.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/trailing_whitespace_rule.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('Trailing Whitespace Validation', () {
    test('passes for line with no trailing whitespace', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}Line without trailing whitespace\n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors, isEmpty);
    });

    test('passes for line with exactly 2 trailing spaces (hard line break)', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}Line with 2 spaces  \nNext line\n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors, isEmpty);
    });

    test('flags line with 1 trailing space as warning', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}Line with 1 space \n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors.any((e) => e.message.contains('has 1 trailing space(s)')), isTrue);
    });

    test('flags line with 3 trailing spaces as warning', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}Line with 3 spaces   \n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors.any((e) => e.message.contains('has 3 trailing space(s)')), isTrue);
    });

    test('flags line with trailing tabs as warning', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}Line with tab\t\n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors.any((e) => e.message.contains('trailing whitespace containing tabs')), isTrue);
    });

    test('respects severity setting', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.error);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}Line with 1 space \n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors.length, 1);
      expect(errors.first.severity, AnalysisSeverity.error);
    });

    test(
      r'flags line with 1 trailing space before Windows line ending (\r\n) as warning',
      () async {
        final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
        final context = SkillContext(
          directory: Directory('dummy'),
          rawContent: '${buildFrontmatter(name: 'test-skill')}Line with 1 space \r\n',
        );

        final List<ValidationError> errors = await rule.validate(context);

        expect(errors.any((e) => e.message.contains('has 1 trailing space(s)')), isTrue);
      },
    );

    test('flags line containing only whitespace (3 spaces) as warning', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}   \n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors.any((e) => e.message.contains('has 3 trailing space(s)')), isTrue);
    });

    test('passes for line containing only 2 spaces', () async {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);
      final context = SkillContext(
        directory: Directory('dummy'),
        rawContent: '${buildFrontmatter(name: 'test-skill')}  \n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors, isEmpty);
    });

    group('Trailing Whitespace Region Calculation', () {
      test('calculates correct start and end columns for spaces', () {
        final SourceRegion region = TrailingWhitespaceRule.calculateTrailingWhitespaceRegion(
          lineNumber: 5,
          trimmedLine: 'Hello world   ',
          whitespace: '   ',
        );

        expect(region.startLine, equals(5));
        expect(region.startColumn, equals(12));
        expect(region.endLine, equals(5));
        expect(region.endColumn, equals(15));
      });

      test('calculates correct start and end columns for single tab', () {
        final SourceRegion region = TrailingWhitespaceRule.calculateTrailingWhitespaceRegion(
          lineNumber: 10,
          trimmedLine: 'Indent\t',
          whitespace: '\t',
        );

        expect(region.startLine, equals(10));
        expect(region.startColumn, equals(7));
        expect(region.endLine, equals(10));
        expect(region.endColumn, equals(8));
      });
    });

    group('Trailing Whitespace Fix', () {
      test('removes trailing whitespace', () {
        final rule = TrailingWhitespaceRule();

        expect(rule.fixLine('Line with 1 space '), 'Line with 1 space');
        expect(rule.fixLine('Line with 3 spaces   '), 'Line with 3 spaces');
        expect(rule.fixLine('Line with tab\t'), 'Line with tab');
      });

      test('keeps exactly 2 spaces', () {
        final rule = TrailingWhitespaceRule();

        expect(rule.fixLine('Line with 2 spaces  '), 'Line with 2 spaces  ');
      });

      test('handles Windows line endings', () {
        final rule = TrailingWhitespaceRule();

        expect(rule.fixLine('Line with 1 space \r'), 'Line with 1 space\r');
        expect(rule.fixLine('Line with 3 spaces   \r'), 'Line with 3 spaces\r');
      });
    });

    group('Trailing Whitespace edge cases', () {
      final rule = TrailingWhitespaceRule(severity: AnalysisSeverity.warning);

      Future<List<String>> diagnose(String content) async {
        final List<ValidationError> errors = await rule.validate(
          SkillContext(directory: Directory('dummy'), rawContent: content),
        );
        return errors.map(_describe).toList();
      }

      Future<String> fix(String content) => rule.fix('SKILL.md', content, Directory('dummy'));

      final cases = <({String name, String content, List<String> errors, String fixed})>[
        (name: 'empty file', content: '', errors: [], fixed: ''),
        (name: 'only a newline', content: '\n', errors: [], fixed: '\n'),
        (
          name: 'one tab',
          content: 'a\t\n',
          errors: ['1:2-3 Line 1 has trailing whitespace containing tabs.'],
          fixed: 'a\n',
        ),
        (
          name: 'two tabs',
          content: 'a\t\t\n',
          errors: ['1:2-4 Line 1 has trailing whitespace containing tabs.'],
          fixed: 'a\n',
        ),
        (
          name: 'two spaces then a tab',
          content: 'a  \t\n',
          errors: ['1:2-5 Line 1 has trailing whitespace containing tabs.'],
          fixed: 'a\n',
        ),
        (
          name: 'tab then two spaces',
          content: 'a\t  \n',
          errors: ['1:2-5 Line 1 has trailing whitespace containing tabs.'],
          fixed: 'a\n',
        ),
        (
          name: 'whitespace inside the line is ignored',
          content: 'a \t b\n',
          errors: [],
          fixed: 'a \t b\n',
        ),
        (
          name: 'CRLF with three spaces',
          content: 'a   \r\nb\r\n',
          errors: [
            '1:2-5 Line 1 has 3 trailing space(s). Only exactly 2 spaces are allowed for line breaks.',
          ],
          fixed: 'a\r\nb\r\n',
        ),
        (name: 'CRLF with two spaces', content: 'a  \r\n', errors: [], fixed: 'a  \r\n'),
        (
          name: 'CRLF with a tab',
          content: 'a\t\r\n',
          errors: ['1:2-3 Line 1 has trailing whitespace containing tabs.'],
          fixed: 'a\r\n',
        ),
        (
          name: 'space before two carriage returns is not trailing',
          content: 'a \r\r\n',
          errors: [],
          fixed: 'a \r\r\n',
        ),
        (
          name: 'final line without a newline',
          content: 'a\nb ',
          errors: [
            '2:2-3 Line 2 has 1 trailing space(s). Only exactly 2 spaces are allowed for line breaks.',
          ],
          fixed: 'a\nb',
        ),
        (
          name: 'file that is only one space',
          content: ' ',
          errors: [
            '1:1-2 Line 1 has 1 trailing space(s). Only exactly 2 spaces are allowed for line breaks.',
          ],
          fixed: '',
        ),
        (
          name: 'line that is only a tab',
          content: 'a\n\t\nb\n',
          errors: ['2:1-2 Line 2 has trailing whitespace containing tabs.'],
          fixed: 'a\n\nb\n',
        ),
        (
          name: 'line that is only spaces before CRLF',
          content: '    \r\n',
          errors: [
            '1:1-5 Line 1 has 4 trailing space(s). Only exactly 2 spaces are allowed for line breaks.',
          ],
          fixed: '\r\n',
        ),
        (
          name: 'several lines',
          content: 'a \nb  \nc   \nd\t\ne',
          errors: [
            '1:2-3 Line 1 has 1 trailing space(s). Only exactly 2 spaces are allowed for line breaks.',
            '3:2-5 Line 3 has 3 trailing space(s). Only exactly 2 spaces are allowed for line breaks.',
            '4:2-3 Line 4 has trailing whitespace containing tabs.',
          ],
          fixed: 'a\nb  \nc\nd\ne',
        ),
      ];

      for (final c in cases) {
        test('${c.name}: diagnostics', () async {
          expect(await diagnose(c.content), c.errors, reason: 'content: ${_escape(c.content)}');
        });

        test('${c.name}: fix output', () async {
          expect(
            _escape(await fix(c.content)),
            _escape(c.fixed),
            reason: 'content: ${_escape(c.content)}',
          );
        });
      }

      test('matches the regular-expression implementation on seeded random input', () async {
        // Any seed works. A fixed seed makes a failure reproducible.
        final random = Random(23);
        const alphabet = ['a', 'b', ' ', ' ', '\t', '\r', '\n', '\n'];
        for (var i = 0; i < 2000; i++) {
          final String content = [
            for (int n = random.nextInt(24); n > 0; n--) alphabet[random.nextInt(alphabet.length)],
          ].join();
          final String input = _escape(content);
          expect(
            await diagnose(content),
            _referenceDiagnostics(content),
            reason: 'content: $input',
          );
          expect(_escape(await fix(content)), _escape(_referenceFix(content)), reason: input);
        }
      });
    });
  });
}

/// Formats [error] as `line:startColumn-endColumn message`.
String _describe(ValidationError error) {
  final SourceRegion region = error.region!;
  expect(region.endLine, region.startLine, reason: 'a trailing whitespace region spans one line');
  return '${region.startLine}:${region.startColumn}-${region.endColumn} ${error.message}';
}

String _escape(String s) =>
    s.replaceAll('\r', r'\r').replaceAll('\n', r'\n').replaceAll('\t', r'\t');

/// A regular expression for trailing whitespace. The rule's hand-written
/// scan must give the same results as this reference.
final RegExp _referenceRegExp = RegExp(r'([ \t]+)$');

/// The diagnostics of the regular-expression implementation, in the format
/// of [_describe].
List<String> _referenceDiagnostics(String content) {
  final result = <String>[];
  final List<String> lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i].endsWith('\r')
        ? lines[i].substring(0, lines[i].length - 1)
        : lines[i];
    final String? whitespace = _referenceRegExp.firstMatch(line)?.group(1);
    if (whitespace == null) {
      continue;
    }
    final columns = '${i + 1}:${line.length - whitespace.length + 1}-${line.length + 1}';
    if (whitespace.contains('\t')) {
      result.add('$columns Line ${i + 1} has trailing whitespace containing tabs.');
    } else if (whitespace.length != 2) {
      result.add(
        '$columns Line ${i + 1} has ${whitespace.length} trailing space(s). '
        'Only exactly 2 spaces are allowed for line breaks.',
      );
    }
  }
  return result;
}

/// The `--fix` output of the regular-expression implementation.
String _referenceFix(String content) => content
    .split('\n')
    .map((String line) {
      final bool hasCR = line.endsWith('\r');
      final String body = hasCR ? line.substring(0, line.length - 1) : line;
      final String? whitespace = _referenceRegExp.firstMatch(body)?.group(1);
      if (whitespace == null || whitespace == '  ') {
        return line;
      }
      final String fixed = body.replaceAll(_referenceRegExp, '');
      return hasCR ? '$fixed\r' : fixed;
    })
    .join('\n');
