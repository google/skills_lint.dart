// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/validation_error.dart';

/// Enforces that published package skills follow the naming convention required
/// by `package:skills`.
///
/// Published skills in a Dart package's `skills/` directory must start with
/// the package name (or the package name with underscores replaced by hyphens)
/// followed by a hyphen (e.g. `skills-lint-setup` or `skills_lint-setup` for
/// package `skills_lint`).
class PublishedSkillNameRule extends SkillRule implements FixableRule {
  PublishedSkillNameRule({this.severity = defaultSeverity, this.packageName, this.pubspecPath});

  static const String ruleName = 'published-skill-name';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;
  static const String packageNameParameter = 'package_name';
  static const String pubspecPathParameter = 'pubspec_path';

  static const String _skillFileName = SkillContext.skillFileName;
  static const String _specUrl = 'https://pub.dev/packages/skills#naming-convention';

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  /// Optional explicit package name override.
  final String? packageName;

  /// Optional explicit path to `pubspec.yaml`.
  final String? pubspecPath;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final List<ValidationError> errors = [];

    if (context.yamlParsingError != null || context.parsedYaml == null) {
      return errors;
    }

    final YamlMap yaml = context.parsedYaml!;
    final YamlNode? nameNode = yaml.nodes['name'];
    final String skillName = nameNode?.value?.toString().trim() ?? '';

    if (skillName.isEmpty) {
      return errors;
    }

    final String? resolvedPackageName = resolvePackageName(
      startDirectory: context.directory,
      explicitPackageName: packageName,
      explicitPubspecPath: pubspecPath,
    );

    if (resolvedPackageName == null || resolvedPackageName.isEmpty) {
      errors.add(
        ValidationError(
          ruleId: name,
          severity: severity,
          file: _skillFileName,
          message:
              'Unable to resolve enclosing Dart package name. Add a '
              'pubspec.yaml in an ancestor directory, configure the '
              'package_name parameter in skills_lint.yaml, or disable the '
              'published-skill-name rule.',
        ),
      );
      return errors;
    }

    final hyphenPrefix = '${resolvedPackageName.replaceAll('_', '-')}-';
    final rawPrefix = '$resolvedPackageName-';

    final bool startsWithValidPrefix =
        skillName.startsWith(hyphenPrefix) || skillName.startsWith(rawPrefix);

    if (!startsWithValidPrefix) {
      final String suggestedName = suggestValidName(skillName, resolvedPackageName);
      final String dirPath = context.directory.path;
      final String targetPath = p.join(p.dirname(dirPath), suggestedName);
      final fixCommand = p.basename(dirPath) == suggestedName
          ? 'dart run skills_lint --fix'
          : 'mv $dirPath $targetPath';
      errors.add(
        ValidationError(
          ruleId: name,
          severity: severity,
          file: _skillFileName,
          message:
              'Skill "$skillName" does not follow the Dart package published skill '
              'naming convention for package "$resolvedPackageName". Published skills '
              'must start with "$hyphenPrefix". '
              'Suggested name: "$suggestedName".\n'
              'Fix with:\n'
              '`$fixCommand`\n'
              '(see $_specUrl)',
        ),
      );
    }

    return errors;
  }

  /// Resolves the enclosing Dart package name from parameters or by walking up
  /// parent directories from [startDirectory] to find `pubspec.yaml`.
  static String? resolvePackageName({
    required Directory startDirectory,
    String? explicitPackageName,
    String? explicitPubspecPath,
  }) {
    if (explicitPackageName != null && explicitPackageName.trim().isNotEmpty) {
      return explicitPackageName.trim();
    }

    if (explicitPubspecPath != null && explicitPubspecPath.trim().isNotEmpty) {
      final file = File(explicitPubspecPath.trim());
      if (file.existsSync()) {
        return _extractPackageNameFromPubspec(file);
      }
      return null;
    }

    Directory current = startDirectory.absolute;
    while (true) {
      final pubspecFile = File(p.join(current.path, 'pubspec.yaml'));
      if (pubspecFile.existsSync()) {
        final String? pkgName = _extractPackageNameFromPubspec(pubspecFile);
        if (pkgName != null && pkgName.isNotEmpty) {
          return pkgName;
        }
      }

      final Directory parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }

    return null;
  }

  static String? _extractPackageNameFromPubspec(File pubspecFile) {
    try {
      final String content = pubspecFile.readAsStringSync();
      final Object? yaml = loadYaml(content);
      if (yaml is YamlMap) {
        final Object? nameVal = yaml['name'];
        if (nameVal != null) {
          return nameVal.toString().trim();
        }
      }
    } catch (_) {
      // Ignore syntax/read errors in pubspec
    }
    return null;
  }

  static final _hyphenTrimRegex = RegExp(r'^-+|-+$');

  /// Suggests a valid skill name complying with the package published skill naming convention.
  ///
  /// Examples:
  /// * `suggestValidName('setup', 'skills_lint')` -> `'skills-lint-setup'`
  /// * `suggestValidName('dart-skills-lint-setup', 'skills_lint')` -> `'skills-lint-setup'`
  /// * `suggestValidName('skills_lint', 'skills_lint')` -> `'skills-lint'`
  @visibleForTesting
  static String suggestValidName(String currentName, String packageName) {
    final String hyphenPkg = packageName.replaceAll('_', '-').toLowerCase();
    final String rawPkg = packageName.toLowerCase();
    final String cleanName = currentName.trim().toLowerCase();

    var remainder = cleanName;
    if (cleanName.contains(hyphenPkg)) {
      final int idx = cleanName.indexOf(hyphenPkg);
      remainder = cleanName.substring(idx + hyphenPkg.length);
    } else if (cleanName.contains(rawPkg)) {
      final int idx = cleanName.indexOf(rawPkg);
      remainder = cleanName.substring(idx + rawPkg.length);
    }

    final String suffix = remainder.replaceAll(_hyphenTrimRegex, '');
    if (suffix.isNotEmpty) {
      return '$hyphenPkg-$suffix';
    }
    return hyphenPkg;
  }

  /// Rewrites the frontmatter `name:` in `SKILL.md` to the suggested
  /// normalized published skill name (`<package-name>-<suffix>`).
  @override
  Future<String> fix(String filePath, String currentContent, Directory directory) async {
    if (filePath != _skillFileName) {
      return currentContent;
    }

    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(currentContent);
    if (match == null) {
      return currentContent;
    }
    final String yamlStr = match.group(1)!;

    final Object? yamlObj;
    try {
      yamlObj = loadYaml(yamlStr);
    } catch (_) {
      return currentContent;
    }

    if (yamlObj is! YamlMap) {
      return currentContent;
    }

    final YamlMap yaml = yamlObj;
    final YamlNode? nameNode = yaml.nodes['name'];
    if (nameNode == null) {
      return currentContent;
    }

    final String? resolvedPackageName = resolvePackageName(
      startDirectory: directory,
      explicitPackageName: packageName,
      explicitPubspecPath: pubspecPath,
    );

    if (resolvedPackageName == null || resolvedPackageName.isEmpty) {
      return currentContent;
    }

    final String currentSkillName = nameNode.value.toString().trim();
    final hyphenPrefix = '${resolvedPackageName.replaceAll('_', '-')}-';
    final rawPrefix = '$resolvedPackageName-';

    if (currentSkillName.startsWith(hyphenPrefix) || currentSkillName.startsWith(rawPrefix)) {
      return currentContent;
    }

    final String suggestedName = suggestValidName(currentSkillName, resolvedPackageName);
    final int yamlOffset = currentContent.indexOf(yamlStr, match.start);
    final SourceSpan span = nameNode.span;
    final String before = currentContent.substring(0, yamlOffset + span.start.offset);
    final String after = currentContent.substring(yamlOffset + span.end.offset);

    return '$before$suggestedName$after';
  }
}
