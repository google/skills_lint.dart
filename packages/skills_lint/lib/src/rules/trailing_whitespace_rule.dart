// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:meta/meta.dart';

import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';

/// Enforces that lines in SKILL.md do not have trailing whitespace,
/// except for exactly two spaces which indicate a hard line break.
class TrailingWhitespaceRule extends SkillRule implements FixableRule {
  TrailingWhitespaceRule({this.severity = defaultSeverity});

  static const String ruleName = 'check-trailing-whitespace';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;
  static final RegExp _whitespaceRegExp = RegExp(r'([ \t]+)$');

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];
    final List<String> lines = context.rawContent.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i];

      // Remove carriage return if present (Windows line endings)
      final String trimmedLine = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

      final RegExpMatch? match = _whitespaceRegExp.firstMatch(trimmedLine);
      if (match != null) {
        final String whitespace = match.group(1)!;
        String? message;
        String? markdownMessage;

        if (whitespace.contains('\t')) {
          message = 'Line ${i + 1} has trailing whitespace containing tabs.';
          markdownMessage =
              '**Line contains trailing whitespace with tabs.**\n\n'
              '**How to fix:**\n'
              '- Remove trailing tabs and whitespace from the end of the line.';
        } else {
          final int spacesCount = whitespace.length;
          if (spacesCount == 1 || spacesCount >= 3) {
            message =
                'Line ${i + 1} has $spacesCount trailing space(s). Only exactly 2 spaces are allowed for line breaks.';
            markdownMessage =
                '**Line contains $spacesCount trailing space(s).**\n\n'
                '**How to fix:**\n'
                '- Remove trailing spaces from the end of the line.\n'
                '- *(Note: exactly 2 trailing spaces are permitted for Markdown hard line breaks).*';
          }
        }

        if (message != null) {
          final int startCol = trimmedLine.length - whitespace.length + 1;
          final int endCol = trimmedLine.length + 1;
          errors.add(
            ValidationError(
              ruleId: name,
              severity: severity,
              file: 'SKILL.md',
              message: message,
              markdownMessage: markdownMessage,
              region: SourceRegion(
                startLine: i + 1,
                startColumn: startCol,
                endLine: i + 1,
                endColumn: endCol,
              ),
            ),
          );
        }
      }
    }

    return errors;
  }

  @override
  Future<String> fix(String filePath, String currentContent, Directory directory) async {
    if (filePath != 'SKILL.md') {
      return currentContent;
    }

    return currentContent.split('\n').map(fixLine).join('\n');
  }

  @visibleForTesting
  String fixLine(String line) {
    final bool hasCR = line.endsWith('\r');
    final String lineWithoutCR = hasCR ? line.substring(0, line.length - 1) : line;

    final RegExpMatch? match = _whitespaceRegExp.firstMatch(lineWithoutCR);
    if (match == null) {
      return line;
    }

    final String whitespace = match.group(1)!;
    if (whitespace == '  ') {
      return line; // Keep the 2 space hard line break.
    }

    final String fixedLine = lineWithoutCR.replaceAll(_whitespaceRegExp, '');
    return hasCR ? '$fixedLine\r' : fixedLine;
  }
}
