// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import '../path_utils.dart';
import '../skill_links.dart';
import '../suggestions/sibling_suggestion.dart';

/// Enforces that relative links in SKILL.md point to existing files.
///
/// Turn on [withinSkill] for skills that must be portable. It reports links
/// that leave the skill directory, which break when the skill is copied
/// somewhere else on its own.
class RelativePathsRule extends SkillRule {
  RelativePathsRule({this.severity = defaultSeverity, bool? withinSkill})
    : withinSkill = withinSkill ?? false;

  static const String ruleName = 'check-relative-paths';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  /// The rule parameter that turns on [withinSkill].
  static const String withinSkillParameter = 'within-skill';

  /// Whether to report relative links that resolve outside the skill
  /// directory, including links into sibling skills.
  @visibleForTesting
  final bool withinSkill;

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
      final String path = linkTargetOf(fullPath);

      // Skip absolute paths (handled by AbsolutePathsRule)
      if (isAbsoluteLink(path)) {
        continue;
      }

      if (isUrlOrAnchor(path)) {
        continue; // Ignore web URLs, email links, anchors, etc.
      }

      final String effectivePath = linkFilePath(path);

      final String skillPath = absolute(normalize(context.directory.path));
      final String resolvedPath = absolute(normalize(join(skillPath, effectivePath)));
      final int line = context.offsetToLine(frontmatterEnd + linkMatch.start);
      if (withinSkill && !isAtOrWithin(skillPath, resolvedPath)) {
        // The link is wrong wherever it points, so skip the existence check
        // and the sibling suggestion below.
        errors.add(_outsideSkillError(path: path, resolvedPath: resolvedPath, line: line));
        continue;
      }
      final linkedFile = File(resolvedPath);
      if (!linkedFile.existsSync()) {
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

  /// Reports that the link target [path], found on [line], resolves to
  /// [resolvedPath], outside the skill directory.
  ValidationError _outsideSkillError({
    required String path,
    required String resolvedPath,
    required int line,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Linked file is outside the skill directory: $path (resolved to $resolvedPath). '
          'The link breaks when the skill is installed on its own. Link to an absolute URL, '
          'or copy the content into the skill directory.',
      markdownMessage:
          '**Linked file is outside the skill directory:** `$path`\n\n'
          'The link breaks when the skill is installed on its own.\n\n'
          '**How to fix:**\n'
          '- Link to an absolute URL, such as the file on GitHub or pub.dev.\n'
          '- Or copy the content into the skill directory and link to the copy.',
      region: SourceRegion(startLine: line),
    );
  }
}

/// Looks for a near-miss sibling **file** next to the missing
/// [resolvedPath] and, if one exists, returns the full suggested link as
/// it should appear in the SKILL.md author's markdown — the original
/// link's directory prefix joined to the matched basename, normalized to
/// forward slashes so the suggestion is portable across platforms.
///
/// Returns `null` when:
/// - the original link has no parent dir on disk,
/// - the parent dir can't be listed (e.g. permission error),
/// - no candidate is close enough to the missing basename,
/// - or two candidates are equally close.
///
/// [originalLink] is the link text as written in the SKILL.md
/// (`docs/DEATILS.md`); [resolvedPath] is the same link resolved
/// against the skill directory (`/abs/path/skill/docs/DEATILS.md`).
///
/// Subdirectories of the parent are intentionally excluded from the
/// candidate set — links almost always point at files, and suggesting
/// a directory would be misleading.
@visibleForTesting
String? findSiblingSuggestion({required String originalLink, required String resolvedPath}) {
  final String? best = closestSiblingName(
    Directory(dirname(resolvedPath)),
    basename(resolvedPath),
    kind: SiblingKind.file,
  );
  if (best == null) {
    return null;
  }

  final String dir = dirname(originalLink);
  if (dir == '.' || dir.isEmpty) {
    return best;
  }
  return join(dir, best).replaceAll(r'\', '/');
}
