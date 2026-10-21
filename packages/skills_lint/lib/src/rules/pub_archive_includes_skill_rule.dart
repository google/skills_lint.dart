// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/analysis_severity.dart';
import '../models/pub_archive.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import '../skill_links.dart';

/// Checks that `dart pub publish` uploads each skill in a package's `skills/`
/// directory, and every file the skill links to.
///
/// `dart run skills@ get` installs skills from the published package. A
/// `.pubignore` or `.gitignore` pattern can drop a skill from the archive with
/// no warning, and a path dependency hides the problem because it ignores
/// `.pubignore`.
///
/// The rule reads the file list from [SkillContext.pubArchive]. Skills
/// outside `<package root>/skills/` pass, because pub does not install them.
class PubArchiveIncludesSkillRule extends SkillRule {
  PubArchiveIncludesSkillRule({this.severity = defaultSeverity});

  static const String ruleName = 'pub-archive-includes-skill';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  /// The directory, under the package root, that `dart run skills@ get` reads.
  static const String skillsDirectoryName = 'skills';

  static const String _howToFix = 'Check .pubignore and .gitignore.';

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    switch (context.pubArchive) {
      case null:
        return [
          _error(
            '$ruleName needs the list of files pub publishes, which validateSkills and the '
            'skills_lint command provide. This run did not provide it.',
          ),
        ];
      case PubArchiveUnavailable(:final String reason):
        return [_error(reason)];
      case PubArchiveFiles(:final String packageRoot, :final Set<String> files):
        return _missingFiles(context, packageRoot: packageRoot, files: files);
    }
  }

  List<ValidationError> _missingFiles(
    SkillContext context, {
    required String packageRoot,
    required Set<String> files,
  }) {
    final String skillPath = p.normalize(context.directory.absolute.path);
    final String skillsPath = p.join(packageRoot, skillsDirectoryName);
    if (p.dirname(skillPath) != skillsPath) {
      return const [];
    }
    final String skillName = p.basename(skillPath);

    final String skillFile = _archivePath(
      packageRoot,
      p.join(skillPath, SkillContext.skillFileName),
    );
    if (!files.contains(skillFile)) {
      // Without SKILL.md nothing is installed, so its links don't matter.
      return [
        _error(
          '$skillFile is not in the package pub publishes, so `dart run skills@ get` '
          "won't install $skillName. $_howToFix",
        ),
      ];
    }

    final errors = <ValidationError>[];
    final RegExpMatch? frontmatter = SkillContext.skillStartRegex.firstMatch(context.rawContent);
    final int bodyStart = frontmatter?.end ?? 0;
    final String body = context.rawContent.substring(bodyStart);
    for (final RegExpMatch link in SkillContext.markdownLinkRegex.allMatches(body)) {
      final String target = linkTargetOf(link[1]!);
      if (isAbsoluteLink(target) || isUrlOrAnchor(target)) {
        continue;
      }
      final String linkedPath = p.normalize(p.join(skillPath, linkFilePath(target)));
      // check-relative-paths reports links to files that don't exist. Pub
      // doesn't publish files outside the package.
      if (!p.isWithin(packageRoot, linkedPath) || !File(linkedPath).existsSync()) {
        continue;
      }
      final String linkedFile = _archivePath(packageRoot, linkedPath);
      if (!files.contains(linkedFile)) {
        errors.add(
          _error(
            '$linkedFile, linked from $skillFile, is not in the package pub publishes, so '
            'the link is broken in installed copies of $skillName. $_howToFix',
            region: SourceRegion(startLine: context.offsetToLine(bodyStart + link.start)),
          ),
        );
      }
    }
    return errors;
  }

  /// The archive entry name for [path], a file inside [packageRoot].
  static String _archivePath(String packageRoot, String path) =>
      p.split(p.relative(path, from: packageRoot)).join('/');

  ValidationError _error(String message, {SourceRegion? region}) => ValidationError(
    ruleId: name,
    severity: severity,
    file: SkillContext.skillFileName,
    message: message,
    region: region,
  );
}
