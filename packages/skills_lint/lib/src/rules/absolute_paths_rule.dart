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
import '../skill_links.dart';

/// Enforces that links in SKILL.md do not use absolute paths.
class AbsolutePathsRule extends SkillRule implements FixableRule {
  AbsolutePathsRule({this.severity = defaultSeverity});

  static const String ruleName = 'check-absolute-paths';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.warning;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

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
      final String path = linkTargetOf(fullPath);

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
      file: SkillContext.skillFileName,
      // RULES.md documents this subject format. Changing it is a breaking change.
      subject: path,
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
  Future<String> fix(SkillContext context) async {
    final String currentContent = context.rawContent;

    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(currentContent);
    final int frontmatterEnd = match != null ? match.end : 0;
    final String frontmatter = currentContent.substring(0, frontmatterEnd);
    final String markdownContent = currentContent.substring(frontmatterEnd);

    final String physicalSkillPath = _physicalPath(context.directory);
    final String fixedMarkdown = markdownContent.replaceAllMapped(SkillContext.markdownLinkRegex, (
      match,
    ) {
      final String rawTarget = match[1]!;
      final String trimmed = rawTarget.trim();
      final List<String> parts = trimmed.split(RegExp(r'\s+'));
      final String pathOnly = parts.first;
      final String? titlePart = parts.length > 1 ? trimmed.substring(pathOnly.length) : null;

      if (isAbsolute(pathOnly) || windows.isAbsolute(pathOnly)) {
        final file = File(pathOnly);
        if (file.existsSync()) {
          final String posixRelativePath = _relativeLink(
            target: file,
            pathOnly: pathOnly,
            skillDirectory: context.directory,
            physicalSkillPath: physicalSkillPath,
          );
          final targetWithTitle = titlePart != null
              ? '$posixRelativePath$titlePart'
              : posixRelativePath;
          final String fullMatch = match[0]!;
          final int targetStart = fullMatch.length - rawTarget.length - 1;
          return '${fullMatch.substring(0, targetStart)}$targetWithTitle)';
        }
      }

      return match[0]!;
    });

    return '$frontmatter$fixedMarkdown';
  }

  /// Relative POSIX link from [skillDirectory] to [target].
  ///
  /// [pathOnly] is the link destination from `SKILL.md`, and
  /// [physicalSkillPath] is [skillDirectory] with symbolic links resolved.
  /// Uses the physical relative path when it resolves lexically from
  /// [skillDirectory] to [target], and the lexical path from [skillDirectory]
  /// otherwise.
  static String _relativeLink({
    required File target,
    required String pathOnly,
    required Directory skillDirectory,
    required String physicalSkillPath,
  }) {
    final String targetPath = _physicalPath(target);
    final String physical = relative(targetPath, from: physicalSkillPath);
    // `check-relative-paths` resolves `../` segments lexically from
    // `skillDirectory`, so a physical `../` path fails there when
    // `skillDirectory` is a symlink to a directory at a different depth.
    final String chosen = _resolvesTo(skillDirectory, physical, targetPath)
        ? physical
        : relative(pathOnly, from: skillDirectory.path);
    return chosen.replaceAll(r'\', '/');
  }

  /// Whether [relativeLink], joined lexically onto [skillDirectory], points to
  /// [targetPath] on disk.
  static bool _resolvesTo(Directory skillDirectory, String relativeLink, String targetPath) {
    final resolved = File(normalize(join(skillDirectory.path, relativeLink)));
    return resolved.existsSync() && equals(_physicalPath(resolved), targetPath);
  }

  /// Path of [entity] with symbolic links resolved, falling back to
  /// [FileSystemEntity.path] on [FileSystemException].
  static String _physicalPath(FileSystemEntity entity) {
    try {
      return entity.resolveSymbolicLinksSync();
    } on FileSystemException {
      return entity.path;
    }
  }
}
