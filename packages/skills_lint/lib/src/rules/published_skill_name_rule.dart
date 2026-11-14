// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import '../name_prefix.dart';

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
      errors.add(_buildUnresolvedPackageNameError());
      return errors;
    }

    if (!_hasPackagePrefix(skillName, resolvedPackageName)) {
      final SourceRegion? region = context.yamlNodeToRegion(nameNode);
      final String suggestedName = suggestPrefixedName(
        currentName: skillName,
        prefix: resolvedPackageName,
      );
      errors.add(
        _buildNamingConventionError(
          skillName: skillName,
          packageName: resolvedPackageName,
          hyphenPrefix: '${_hyphenatedPackageName(resolvedPackageName)}-',
          suggestedName: suggestedName,
          region: region,
        ),
      );
    }

    return errors;
  }

  ValidationError _buildUnresolvedPackageNameError() {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      message:
          'Unable to resolve enclosing Dart package name. Add a '
          'pubspec.yaml in an ancestor directory, configure the '
          'package_name parameter in skills_lint.yaml, or disable the '
          'published-skill-name rule.',
      markdownMessage:
          '**Unable to resolve enclosing Dart package name.**\n\n'
          '**How to fix:**\n'
          '- Add a `pubspec.yaml` in an ancestor directory, or\n'
          '- Configure the `package_name` parameter in `skills_lint.yaml`, or\n'
          '- Disable the `published-skill-name` rule.',
    );
  }

  ValidationError _buildNamingConventionError({
    required String skillName,
    required String packageName,
    required String hyphenPrefix,
    required String suggestedName,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      message:
          'Skill "$skillName" does not follow the Dart package published skill '
          'naming convention for package "$packageName". Published skills '
          'must start with "$hyphenPrefix". '
          'Suggested name: "$suggestedName".\n'
          'Fix by re-running your validation command with `--fix`.\n'
          '(see $_specUrl)',
      markdownMessage:
          '**Skill name does not follow Dart package published skill naming convention.**\n\n'
          'Published skills in package `$packageName` must start with `$hyphenPrefix`.\n\n'
          '* **Current:** `$skillName`\n'
          '* **Suggested:** `$suggestedName`\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'name: $suggestedName\n'
          '```\n'
          '*(Or re-run validation with `--fix` to apply automatically).*\n\n'
          '*(See [Agent Skills Naming Convention]($_specUrl))*',
      region: region,
    );
  }

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
    final String content;
    try {
      content = pubspecFile.readAsStringSync();
    } on FileSystemException {
      // Unreadable (permissions, invalid UTF-8): treat as having no package
      // name so the caller keeps searching parent directories.
      return null;
    }
    final Pubspec pubspec;
    try {
      pubspec = Pubspec.parse(content);
    } on Exception {
      // Pubspec.parse reports malformed YAML and invalid fields as
      // ParsedYamlException from package:checked_yaml. That package is not a
      // direct dependency, so match on Exception, which still lets Errors
      // from bugs escape.
      return null;
    }
    final String name = pubspec.name.trim();
    return name.isNotEmpty ? name : null;
  }

  /// Whether [skillName] starts with [packageName], as written or with its
  /// underscores replaced by hyphens.
  static bool _hasPackagePrefix(String skillName, String packageName) =>
      hasNamePrefix(skillName, _hyphenatedPackageName(packageName)) ||
      hasNamePrefix(skillName, packageName.toLowerCase());

  static String _hyphenatedPackageName(String packageName) =>
      packageName.replaceAll('_', '-').toLowerCase();

  @override
  Future<String> fix(SkillContext context, {Set<String> ignoredSubjects = const {}}) async {
    final String? resolvedPackageName = resolvePackageName(
      startDirectory: context.directory,
      explicitPackageName: packageName,
      explicitPubspecPath: pubspecPath,
    );

    if (resolvedPackageName == null || resolvedPackageName.isEmpty) {
      return context.rawContent;
    }

    return renameSkillInFrontmatter(
      context.rawContent,
      (String currentName) => _hasPackagePrefix(currentName, resolvedPackageName)
          ? null
          : suggestPrefixedName(currentName: currentName, prefix: resolvedPackageName),
    );
  }
}
