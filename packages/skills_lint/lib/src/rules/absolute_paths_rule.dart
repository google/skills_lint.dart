// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../fixable_rule.dart';
import '../markdown_links.dart';
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

    for (final MarkdownLink link in bodyLinksOf(context)) {
      final String path = link.target;

      if (isAbsoluteLink(path)) {
        final int line = context.offsetToLine(link.start);
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

    final SkillPathPair skillLocation = (
      logical: context.directory.path,
      physical: _physicalPath(context.directory),
    );
    final fixed = StringBuffer();
    var copiedUpTo = 0;
    for (final MarkdownLink link in bodyLinksOf(context)) {
      final String pathOnly = link.target;
      if (ignoredSubjects.contains(pathOnly)) {
        continue;
      }

      if (isAbsoluteLink(pathOnly)) {
        final file = File(pathOnly);
        if (file.existsSync()) {
          final String posixRelativePath = relativeSkillLink(
            skillDirectory: skillLocation,
            targetFile: (logical: pathOnly, physical: _physicalPath(file)),
          );
          // A space or parenthesis ends a destination unless < and > enclose it.
          final bool needsBrackets =
              !link.isAngleBracketed && posixRelativePath.contains(RegExp(r'[\s()]'));
          fixed
            ..write(currentContent.substring(copiedUpTo, link.targetStart))
            ..write(needsBrackets ? '<$posixRelativePath>' : posixRelativePath);
          copiedUpTo = link.targetEnd;
        }
      }
    }
    fixed.write(currentContent.substring(copiedUpTo));
    return fixed.toString();
  }

  /// Forward-slash relative link text to write into `SKILL.md` for [targetFile].
  ///
  /// Computes the path from the `physical` (symlink-resolved) paths when
  /// [targetFile] resolves inside [skillDirectory], so a link into the skill
  /// stays inside the skill directory even when either path goes through a
  /// symlink. Otherwise computes the path from the `logical` paths as written,
  /// so `../` segments match the depth of [skillDirectory] as reached.
  @visibleForTesting
  static String relativeSkillLink({
    required SkillPathPair skillDirectory,
    required SkillPathPair targetFile,
    p.Context? pathContext,
  }) {
    final p.Context context = pathContext ?? p.context;
    final bool isInsideSkill =
        context.equals(skillDirectory.physical, targetFile.physical) ||
        context.isWithin(skillDirectory.physical, targetFile.physical);
    final String relativePath = isInsideSkill
        ? context.relative(targetFile.physical, from: skillDirectory.physical)
        : context.relative(targetFile.logical, from: skillDirectory.logical);
    return relativePath.replaceAll(r'\', '/');
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
