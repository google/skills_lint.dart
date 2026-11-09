// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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

      if (isAbsoluteLink(path)) {
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
  Future<String> fix(SkillContext context, {Set<String> ignoredSubjects = const {}}) async {
    final String currentContent = context.rawContent;

    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(currentContent);
    final int frontmatterEnd = match != null ? match.end : 0;
    final String frontmatter = currentContent.substring(0, frontmatterEnd);
    final String markdownContent = currentContent.substring(frontmatterEnd);

    final SkillPathPair skillLocation = (
      logical: context.directory.path,
      physical: _physicalPath(context.directory),
    );
    final String fixedMarkdown = markdownContent.replaceAllMapped(SkillContext.markdownLinkRegex, (
      match,
    ) {
      final String rawTarget = match[1]!;
      final String trimmed = rawTarget.trim();
      final List<String> parts = trimmed.split(RegExp(r'\s+'));
      final String pathOnly = parts.first;
      final String? titlePart = parts.length > 1 ? trimmed.substring(pathOnly.length) : null;
      if (ignoredSubjects.contains(pathOnly)) {
        return match[0]!;
      }

      if (isAbsoluteLink(pathOnly)) {
        final file = File(pathOnly);
        if (file.existsSync()) {
          final String posixRelativePath = relativeSkillLink(
            skillDirectory: skillLocation,
            targetFile: (logical: pathOnly, physical: _physicalPath(file)),
            resolveExistingFile: _existingPhysicalPath,
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

  /// Forward-slash relative link text to write into `SKILL.md` for [targetFile].
  ///
  /// Prefers the relative path between the symlink-resolved (`physical`) paths
  /// of [skillDirectory] and [targetFile], so a link into the skill stays
  /// inside the skill directory even when one side goes through a symlink. When
  /// joining that relative path onto `skillDirectory.logical` does not resolve
  /// back to `targetFile.physical` via [resolveExistingFile], falls back to the
  /// relative path between the `logical` paths as written.
  @visibleForTesting
  static String relativeSkillLink({
    required SkillPathPair skillDirectory,
    required SkillPathPair targetFile,
    required String? Function(String candidatePath) resolveExistingFile,
    p.Context? pathContext,
  }) {
    final p.Context context = pathContext ?? p.context;
    final String physicalRelative = context.relative(
      targetFile.physical,
      from: skillDirectory.physical,
    );
    final String candidateFromSkill = context.normalize(
      context.join(skillDirectory.logical, physicalRelative),
    );
    final String? resolvedCandidate = resolveExistingFile(candidateFromSkill);
    // A skill directory reached through a symlink can sit at a different depth
    // than its physical directory (for example `repo/skills/s` ->
    // `store/a/b/c/s`). For a file outside the skill (`repo/README.md`), the
    // `../` count computed from `store/a/b/c/s` climbs the wrong number of
    // levels when joined onto `repo/skills/s` and resolves to the wrong place.
    final bool physicalRelativeResolves =
        resolvedCandidate != null && context.equals(resolvedCandidate, targetFile.physical);
    final String chosen = physicalRelativeResolves
        ? physicalRelative
        : context.relative(targetFile.logical, from: skillDirectory.logical);
    return chosen.replaceAll(r'\', '/');
  }

  /// Physical path of [candidatePath] when the file exists, or `null` when it
  /// does not.
  static String? _existingPhysicalPath(String candidatePath) {
    final resolved = File(candidatePath);
    return resolved.existsSync() ? _physicalPath(resolved) : null;
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

/// An unresolved (`logical`) filesystem path paired with its symlink-resolved
/// (`physical`) path.
@visibleForTesting
typedef SkillPathPair = ({String logical, String physical});
