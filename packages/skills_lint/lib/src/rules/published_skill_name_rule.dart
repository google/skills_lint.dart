// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/validation_error.dart';
import '../path_utils.dart';

/// Enforces that published package skills follow the naming convention required
/// by `package:skills`.
///
/// Published skills in a Dart package's `skills/` directory must match the
/// package name or start with the package name (or the package name with
/// underscores replaced by hyphens) followed by a hyphen (e.g. `skills-lint`,
/// `skills-lint-setup`, or `skills_lint-setup` for package `skills_lint`).
class PublishedSkillNameRule extends SkillRule implements FixableRule {
  PublishedSkillNameRule({this.severity = defaultSeverity, this.packageName, this.pubspecPath});

  static const String ruleName = 'published-skill-name';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;
  static const String packageNameParameter = 'package_name';
  static const String pubspecPathParameter = 'pubspec_path';

  static const String _specUrl = 'https://pub.dev/packages/skills#naming-convention';

  final Map<String, String?> _packageCache = {};

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  /// Optional explicit package name override (configured via `package_name` parameter).
  final String? packageName;

  /// Optional explicit path to `pubspec.yaml` (configured via `pubspec_path` parameter).
  ///
  /// Can be an absolute path or a relative path resolved against the process
  /// working directory (`Directory.current` at CLI invocation).
  ///
  /// If omitted, the rule auto-discovers `pubspec.yaml` by ascending parent
  /// directories starting from the skill's directory ([SkillContext.directory]).
  final String? pubspecPath;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final List<ValidationError> errors = [];

    // Syntax errors and missing frontmatter are reported by ValidYamlMetadataRule.
    if (context.yamlParsingError != null || context.parsedYaml == null) {
      return errors;
    }

    final YamlMap yaml = context.parsedYaml!;
    final YamlNode? nameNode = yaml.nodes['name'];
    final String skillName = nameNode?.value?.toString().trim() ?? '';

    // Missing or empty name is reported as a required-field error by ValidYamlMetadataRule.
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
          file: SkillContext.skillFileName,
          message:
              'Unable to resolve enclosing Dart package name. Add a '
              'pubspec.yaml in an ancestor directory, configure the '
              'package_name parameter in skills_lint.yaml, or disable the '
              'published-skill-name rule.',
        ),
      );
      return errors;
    }

    final String hyphenPkg = resolvedPackageName.replaceAll('_', '-').toLowerCase();
    final String rawPkg = resolvedPackageName.toLowerCase();
    final hyphenPrefix = '$hyphenPkg-';
    final rawPrefix = '$rawPkg-';

    final bool isNameValid =
        skillName == hyphenPkg ||
        skillName == rawPkg ||
        skillName.startsWith(hyphenPrefix) ||
        skillName.startsWith(rawPrefix);

    if (!isNameValid) {
      final String suggestedName = suggestValidName(
        currentName: skillName,
        packageName: resolvedPackageName,
      );
      errors.add(
        ValidationError(
          ruleId: name,
          severity: severity,
          file: SkillContext.skillFileName,
          message:
              'Skill "$skillName" does not follow the Dart package published skill '
              'naming convention for package "$resolvedPackageName". Published skills '
              'must start with "$hyphenPrefix". '
              'Suggested name: "$suggestedName".\n'
              'Fix by re-running your validation command with `--fix`.\n'
              '(see $_specUrl)',
        ),
      );
    }

    return errors;
  }

  /// Resolves the enclosing Dart package name from parameters or by walking up
  /// parent directories from [startDirectory] to find `pubspec.yaml`.
  String? resolvePackageName({
    required Directory startDirectory,
    String? explicitPackageName,
    String? explicitPubspecPath,
  }) {
    if (explicitPackageName != null && explicitPackageName.trim().isNotEmpty) {
      return explicitPackageName.trim();
    }

    final cacheKey = '${startDirectory.absolute.path}::${explicitPubspecPath ?? ''}';
    if (_packageCache.containsKey(cacheKey)) {
      return _packageCache[cacheKey];
    }

    if (explicitPubspecPath != null && explicitPubspecPath.trim().isNotEmpty) {
      final String? pkgName = _resolveFromExplicitPubspec(explicitPubspecPath.trim());
      return _packageCache[cacheKey] = pkgName;
    }

    return _packageCache[cacheKey] = _autoDiscoverPackageName(startDirectory);
  }

  static String? _resolveFromExplicitPubspec(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    return _extractPackageNameFromPubspec(file);
  }

  String? _autoDiscoverPackageName(Directory startDirectory) {
    final visitedPaths = <String>[];
    Directory current = startDirectory.absolute;

    while (true) {
      final dirKey = '${current.path}::';
      if (_packageCache.containsKey(dirKey)) {
        final String? cachedPkg = _packageCache[dirKey];
        _populateCacheForPaths(visitedPaths, cachedPkg);
        return cachedPkg;
      }

      visitedPaths.add(current.path);
      final pubspecFile = File(p.join(current.path, 'pubspec.yaml'));
      if (pubspecFile.existsSync()) {
        final String? pkgName = _extractPackageNameFromPubspec(pubspecFile);
        if (pkgName != null && pkgName.isNotEmpty) {
          _populateCacheForPaths(visitedPaths, pkgName);
          return pkgName;
        }
      }

      final Directory parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }

    _populateCacheForPaths(visitedPaths, null);
    return null;
  }

  void _populateCacheForPaths(List<String> paths, String? pkgName) {
    for (final path in paths) {
      _packageCache['$path::'] = pkgName;
    }
  }

  static String? _extractPackageNameFromPubspec(File pubspecFile) {
    try {
      final String content = pubspecFile.readAsStringSync();
      final pubspec = Pubspec.parse(content);
      final String name = pubspec.name.trim();
      return name.isNotEmpty ? name : null;
    } catch (_) {
      // Ignore syntax/read errors in pubspec
    }
    return null;
  }

  /// Suggests a valid skill name complying with the package published skill naming convention.
  ///
  /// Examples:
  /// * `suggestValidName(currentName: 'setup', packageName: 'skills_lint')` -> `'skills-lint-setup'`
  /// * `suggestValidName(currentName: 'dart-skills-lint-setup', packageName: 'skills_lint')` -> `'skills-lint-setup'`
  /// * `suggestValidName(currentName: 'skills_lint_setup', packageName: 'skills_lint')` -> `'skills-lint-setup'`
  /// * `suggestValidName(currentName: 'skills_lint', packageName: 'skills_lint')` -> `'skills-lint'`
  @visibleForTesting
  static String suggestValidName({required String currentName, required String packageName}) {
    final List<String> pkgTokens = _tokenize(packageName);
    final List<String> skillTokens = _tokenize(currentName);

    if (pkgTokens.isEmpty) {
      return normalizeSkillNameToken(currentName);
    }

    var matchStart = -1;
    for (var i = 0; i <= skillTokens.length - pkgTokens.length; i++) {
      var match = true;
      for (var j = 0; j < pkgTokens.length; j++) {
        if (skillTokens[i + j] != pkgTokens[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        matchStart = i;
        break;
      }
    }

    final List<String> suffixTokens;
    if (matchStart >= 0) {
      final int matchEnd = matchStart + pkgTokens.length;
      final List<String> after = skillTokens.sublist(matchEnd);
      final List<String> before = skillTokens.sublist(0, matchStart);
      suffixTokens = after.isNotEmpty ? after : before;
    } else {
      suffixTokens = skillTokens;
    }

    final resultTokens = [...pkgTokens, ...suffixTokens];
    final String candidate = resultTokens.join('-');
    return normalizeSkillNameToken(candidate);
  }

  static List<String> _tokenize(String input) =>
      input.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((token) => token.isNotEmpty).toList();

  /// Rewrites the frontmatter `name:` in `SKILL.md` to the suggested
  /// normalized published skill name (`<package-name>-<suffix>`).
  @override
  Future<String> fix(String filePath, String currentContent, Directory directory) async {
    if (filePath != SkillContext.skillFileName) {
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
    final String hyphenPkg = resolvedPackageName.replaceAll('_', '-').toLowerCase();
    final String rawPkg = resolvedPackageName.toLowerCase();
    final hyphenPrefix = '$hyphenPkg-';
    final rawPrefix = '$rawPkg-';

    if (currentSkillName == hyphenPkg ||
        currentSkillName == rawPkg ||
        currentSkillName.startsWith(hyphenPrefix) ||
        currentSkillName.startsWith(rawPrefix)) {
      return currentContent;
    }

    final String suggestedName = suggestValidName(
      currentName: currentSkillName,
      packageName: resolvedPackageName,
    );
    final int yamlOffset = currentContent.indexOf(yamlStr, match.start);
    final SourceSpan span = nameNode.span;
    final String before = currentContent.substring(0, yamlOffset + span.start.offset);
    final String after = currentContent.substring(yamlOffset + span.end.offset);

    return '$before$suggestedName$after';
  }
}
