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
/// directory, and every file inside the skill that its `SKILL.md` links to.
///
/// A `.pubignore` or `.gitignore` pattern can drop a skill, or a file it links
/// to, from the published package with no warning. A path dependency hides the
/// problem because it ignores `.pubignore`.
///
/// The rule reads the file list from [SkillContext.pubArchive]. Skills
/// outside `<package root>/skills/` pass. Links that leave the skill
/// directory, and links to files that don't exist, are skipped;
/// `check-relative-paths` reports those when it is enabled.
class PubArchiveIncludesSkillRule extends SkillRule {
  PubArchiveIncludesSkillRule({this.severity = defaultSeverity});

  static const String ruleName = 'pub-archive-includes-skill';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  /// The directory, under the package root, that holds published skills.
  static const String skillsDirectoryName = 'skills';

  static const String _howToFix =
      'Run `dart pub publish --dry-run` to list the files pub publishes, and check .pubignore '
      'and .gitignore.';

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
          '$skillFile is not in the package pub publishes, so the published package has no '
          '$skillName skill. $_howToFix',
        ),
      ];
    }

    // Each link inside the skill whose target exists but is not published,
    // keyed by archive path, with the line of its first link.
    final missing = <String, int>{};
    final RegExpMatch? frontmatter = SkillContext.skillStartRegex.firstMatch(context.rawContent);
    final int bodyStart = frontmatter?.end ?? 0;
    final String body = context.rawContent.substring(bodyStart);
    for (final RegExpMatch link in SkillContext.markdownLinkRegex.allMatches(body)) {
      final String target = linkTargetOf(link[1]!);
      if (isAbsoluteLink(target) || isUrlOrAnchor(target)) {
        continue;
      }
      final String linkedPath = p.normalize(p.join(skillPath, linkFilePath(target)));
      // check-relative-paths reports links to files that don't exist, and,
      // with `within-skill: true`, links that leave the skill.
      if (!p.isWithin(skillPath, linkedPath) || !File(linkedPath).existsSync()) {
        continue;
      }
      final String linkedFile = _archivePath(packageRoot, linkedPath);
      if (!files.contains(linkedFile)) {
        missing.putIfAbsent(linkedFile, () => context.offsetToLine(bodyStart + link.start));
      }
    }
    return [
      for (final MapEntry<String, List<String>> group in _groupByExcludedDirectory(
        missing.keys,
        skillFile: skillFile,
        files: files,
      ).entries)
        _error(
          group.value.length == 1 && group.key == group.value.single
              ? '${group.key}, linked from $skillFile, is not in the package pub publishes. '
                    '$_howToFix'
              : '${group.key}/ is not in the package pub publishes, so neither are the '
                    '${group.value.length} files $skillFile links to in it. $_howToFix',
          region: SourceRegion(startLine: missing[group.value.first]!),
        ),
    ];
  }

  /// Groups each of [missingFiles] under the highest directory between it and
  /// the skill directory that has no file in the archive, or under itself when
  /// no such directory holds another missing file.
  ///
  /// A `.pubignore` pattern often drops a whole directory, such as
  /// `references/`, and one diagnostic for it is easier to act on than one
  /// per file.
  static Map<String, List<String>> _groupByExcludedDirectory(
    Iterable<String> missingFiles, {
    required String skillFile,
    required Set<String> files,
  }) {
    final String skillDirectory = p.posix.dirname(skillFile);
    final groups = <String, List<String>>{};
    for (final file in missingFiles) {
      var key = file;
      for (
        String directory = p.posix.dirname(file);
        directory != skillDirectory;
        directory = p.posix.dirname(directory)
      ) {
        if (!files.any((f) => p.posix.isWithin(directory, f))) {
          key = directory;
        }
      }
      groups.putIfAbsent(key, () => []).add(file);
    }
    // A directory that holds one missing link reads better as that file.
    return {
      for (final MapEntry<String, List<String>> group in groups.entries)
        if (group.value.length == 1) group.value.single: group.value else group.key: group.value,
    };
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
