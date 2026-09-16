// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:path/path.dart';
import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';

/// Enforces that links in SKILL.md do not use absolute paths.
class AbsolutePathsRule extends SkillRule implements FixableRule {
  AbsolutePathsRule({this.severity = defaultSeverity});

  static const String ruleName = 'check-absolute-paths';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.warning;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  static const String _skillFileName = SkillContext.skillFileName;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];

    // Extract content after YAML frontmatter
    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(context.rawContent);
    final int frontmatterEnd = match != null ? match.end : 0;
    final String markdownContent = match != null
        ? context.rawContent.substring(frontmatterEnd)
        : context.rawContent;

    for (final RegExpMatch linkMatch in SkillContext.markdownLinkRegex.allMatches(
      markdownContent,
    )) {
      final String fullPath = linkMatch.group(1)!;
      final String path = fullPath.trim().split(RegExp(r'\s+')).first;

      if (isAbsolute(path) || windows.isAbsolute(path)) {
        final int linkOffsetInFile = frontmatterEnd + linkMatch.start;
        final int line = context.offsetToLine(linkOffsetInFile);
        errors.add(
          _buildAbsolutePathError(
            path: path,
            region: SourceRegion(startLine: line),
          ),
        );
      }
    }

    return errors;
  }

  ValidationError _buildAbsolutePathError({required String path, required SourceRegion region}) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Absolute filepath found in link: $path. '
          'Skills must use paths relative to SKILL.md so they remain '
          'portable across machines.',
      markdownMessage:
          '**Absolute path found in link:** `$path`\n\n'
          '**How to fix:**\n'
          '- Convert `$path` to a relative path pointing inside the skill directory.',
      region: region,
    );
  }

  @override
  Future<String> fix(String filePath, String currentContent, Directory directory) async {
    if (filePath != _skillFileName) {
      return currentContent;
    }

    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(currentContent);
    final int frontmatterEnd = match != null ? match.end : 0;
    final String frontmatter = currentContent.substring(0, frontmatterEnd);
    final String markdownContent = currentContent.substring(frontmatterEnd);

    final String fixedMarkdown = markdownContent.replaceAllMapped(SkillContext.markdownLinkRegex, (
      match,
    ) {
      final String rawTarget = match.group(1)!;
      final String trimmed = rawTarget.trim();

      if (isAbsolute(trimmed) || windows.isAbsolute(trimmed)) {
        final file = File(trimmed);
        if (file.existsSync()) {
          final String relativePath = relative(trimmed, from: directory.path);
          final String posixRelativePath = relativePath.replaceAll(r'\', '/');
          final String fullMatch = match.group(0)!;
          final int lastParen = fullMatch.lastIndexOf('(');
          return '${fullMatch.substring(0, lastParen + 1)}$posixRelativePath)';
        }
      }

      return match.group(0)!;
    });

    return '$frontmatter$fixedMarkdown';
  }
}
