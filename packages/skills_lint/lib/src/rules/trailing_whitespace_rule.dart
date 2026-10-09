// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:meta/meta.dart';
import 'package:source_span/source_span.dart';

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
  static const int _space = 0x20;
  static const int _tab = 0x09;
  static const String _skillFileName = 'SKILL.md';

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  /// Calculates the 1-based source coordinate region corresponding to trailing whitespace.
  @visibleForTesting
  static SourceRegion calculateTrailingWhitespaceRegion({
    required int lineNumber,
    required String trimmedLine,
    required String whitespace,
  }) {
    final int startCol = trimmedLine.length - whitespace.length + 1;
    final int endCol = trimmedLine.length + 1;
    return SourceRegion(
      startLine: lineNumber,
      startColumn: startCol,
      endLine: lineNumber,
      endColumn: endCol,
    );
  }

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];
    // LineSplitter ends lines where SourceFile does, so these line numbers
    // match the ones that SkillContext.offsetToLine gives other rules.
    final List<String> lines = const LineSplitter().convert(context.rawContent);

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final int lineNumber = lineIndex + 1;
      final String line = lines[lineIndex];

      final int whitespaceStart = trailingWhitespaceStart(line);
      if (whitespaceStart == line.length) {
        continue;
      }

      final String whitespace = line.substring(whitespaceStart);
      final SourceRegion region = calculateTrailingWhitespaceRegion(
        lineNumber: lineNumber,
        trimmedLine: line,
        whitespace: whitespace,
      );

      if (whitespace.contains('\t')) {
        errors.add(_buildTabsError(lineNumber: lineNumber, region: region));
      } else {
        final int spacesCount = whitespace.length;
        if (spacesCount == 1 || spacesCount >= 3) {
          errors.add(
            _buildSpacesError(lineNumber: lineNumber, spacesCount: spacesCount, region: region),
          );
        }
      }
    }

    return errors;
  }

  ValidationError _buildTabsError({required int lineNumber, required SourceRegion region}) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message: 'Line $lineNumber has trailing whitespace containing tabs.',
      markdownMessage:
          '**Line contains trailing whitespace with tabs.**\n\n'
          '**How to fix:**\n'
          '- Remove trailing tabs and whitespace from the end of the line.',
      region: region,
    );
  }

  ValidationError _buildSpacesError({
    required int lineNumber,
    required int spacesCount,
    required SourceRegion region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Line $lineNumber has $spacesCount trailing space(s). '
          'Only exactly 2 spaces are allowed for line breaks.',
      markdownMessage:
          '**Line contains $spacesCount trailing space(s).**\n\n'
          '**How to fix:**\n'
          '- Remove trailing spaces from the end of the line.\n'
          '- *(Note: exactly 2 trailing spaces are permitted for Markdown hard line breaks).*',
      region: region,
    );
  }

  @override
  Future<String> fix(String filePath, String currentContent, Directory directory) async {
    if (filePath != _skillFileName) {
      return currentContent;
    }

    // LineSplitter drops the line breaks, which the fix must keep. SourceFile
    // finds the same lines and knows where each starts, so the break after a
    // line is the text from its end to the start of the next line.
    final List<String> lines = const LineSplitter().convert(currentContent);
    final file = SourceFile.fromString(currentContent);
    final fixed = StringBuffer();
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final String line = lines[lineIndex];
      final int lineEnd = file.getOffset(lineIndex) + line.length;
      final int nextLineStart = lineIndex + 1 < file.lines
          ? file.getOffset(lineIndex + 1)
          : currentContent.length;
      fixed
        ..write(fixLine(line))
        ..write(currentContent.substring(lineEnd, nextLineStart));
    }
    return fixed.toString();
  }

  @visibleForTesting
  String fixLine(String line) {
    final int whitespaceStart = trailingWhitespaceStart(line);
    if (whitespaceStart == line.length) {
      return line;
    }

    final String whitespace = line.substring(whitespaceStart);
    if (whitespace == '  ') {
      return line; // Keep the 2 space hard line break.
    }

    return line.substring(0, whitespaceStart);
  }

  /// Returns the index where the run of spaces and tabs at the end of [line]
  /// starts, or `line.length` if [line] doesn't end in a space or tab.
  @visibleForTesting
  static int trailingWhitespaceStart(String line) {
    int start = line.length;
    while (start > 0) {
      final int char = line.codeUnitAt(start - 1);
      if (char != _space && char != _tab) {
        break;
      }
      start--;
    }
    return start;
  }
}
