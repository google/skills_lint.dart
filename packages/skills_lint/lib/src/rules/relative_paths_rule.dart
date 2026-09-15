// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import '../levenshtein.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';

/// Enforces that relative links in SKILL.md point to existing files.
class RelativePathsRule extends SkillRule {
  RelativePathsRule({this.severity = defaultSeverity});

  static const String ruleName = 'check-relative-paths';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  static const _skillFileName = 'SKILL.md';

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
      // Markdown links can have a title after the URL, separated by spaces.
      final String path = fullPath.trim().split(RegExp(r'\s+')).first;

      // Skip absolute paths (handled by AbsolutePathsRule)
      if (isAbsolute(path) || windows.isAbsolute(path)) {
        continue;
      }

      var effectivePath = path;
      try {
        final Uri uri = Uri.parse(path);
        if (uri.hasScheme || path.startsWith('#')) {
          continue; // Ignore web URLs, email links, anchors, etc.
        }
        effectivePath = uri.path;
      } catch (_) {
        // If Uri parsing fails, treat it as a potential filepath.
      }

      final String resolvedPath = absolute(normalize(join(context.directory.path, effectivePath)));
      final linkedFile = File(resolvedPath);
      if (!linkedFile.existsSync()) {
        final int linkOffsetInFile = frontmatterEnd + linkMatch.start;
        final int line = context.offsetToLine(linkOffsetInFile);
        final String? suggestion = findSiblingSuggestion(
          originalLink: path,
          resolvedPath: resolvedPath,
        );
        final suggestionClause = suggestion != null ? ' Did you mean "$suggestion"?' : '';
        final String skillDirName = basename(context.directory.path);
        final suggestionMarkdown = suggestion != null ? '\n\n*Did you mean `$suggestion`?*' : '';
        errors.add(
          ValidationError(
            ruleId: name,
            severity: severity,
            file: _skillFileName,
            message:
                'Linked file does not exist: $path (resolved to $resolvedPath).'
                '$suggestionClause',
            markdownMessage:
                '**Linked file does not exist:** `$path`\n\n'
                '**How to fix:**\n'
                '- Check for typos in `$path`.\n'
                '- Ensure the target file exists relative to this skill directory (`$skillDirName/`).'
                '$suggestionMarkdown',
            region: SourceRegion(startLine: line),
          ),
        );
      }
    }

    return errors;
  }
}

/// Looks for a near-miss sibling **file** next to the missing
/// [resolvedPath] and, if one exists, returns the full suggested link.
@visibleForTesting
String? findSiblingSuggestion({required String originalLink, required String resolvedPath}) {
  final String parentPath = dirname(resolvedPath);
  final parentDir = Directory(parentPath);
  if (!parentDir.existsSync()) {
    return null;
  }

  final String missingBase = basename(resolvedPath).toLowerCase();
  if (missingBase.isEmpty) {
    return null;
  }

  final int threshold = (missingBase.length ~/ 3).clamp(1, missingBase.length);

  final List<FileSystemEntity> entries;
  try {
    entries = parentDir.listSync();
  } on FileSystemException {
    return null;
  }

  String? best;
  int bestDistance = threshold + 1;
  for (final entity in entries) {
    if (entity is Directory) {
      continue;
    }
    final String candidate = basename(entity.path);
    if (candidate == basename(resolvedPath)) {
      continue;
    }
    final int distance = levenshtein(missingBase, candidate.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }

  if (best == null || bestDistance > threshold) {
    return null;
  }

  final String dir = dirname(originalLink);
  if (dir == '.' || dir.isEmpty) {
    return best;
  }
  return join(dir, best).replaceAll(r'\', '/');
}
