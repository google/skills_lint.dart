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
import '../suggestions/sibling_suggestion.dart';

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

      final String? effectivePath = _filePathOf(path);
      if (effectivePath == null) {
        continue; // Ignore web URLs, email links, anchors, etc.
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

  /// Returns the file path that the link target [path] points to, with
  /// percent escapes decoded, or `null` if [path] is a URL with a scheme or
  /// an anchor.
  ///
  /// A [path] that is not a valid URI, whose escapes are not valid UTF-8,
  /// such as `%E9`, or that decodes to an absolute path or to one with a NUL,
  /// is returned as written.
  static String? _filePathOf(String path) {
    final Uri? uri = Uri.tryParse(path);
    if (uri == null) {
      return path;
    }
    if (uri.hasScheme || path.startsWith('#')) {
      return null;
    }
    final String decoded;
    try {
      decoded = Uri.decodeComponent(uri.path);
    } on FormatException {
      // Uri.tryParse turns a % that starts no escape into %25, so only invalid
      // UTF-8, such as %E9, makes decoding fail.
      return path;
    }
    // join would ignore the skill directory for an absolute path, and
    // File.existsSync ignores everything after a NUL.
    if (isAbsolute(decoded) || decoded.contains('\u0000')) {
      return path;
    }
    return decoded;
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
