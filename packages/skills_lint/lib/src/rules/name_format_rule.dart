// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';
import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import '../path_utils.dart';

/// Enforces constraints on the skill name field.
class NameFormatRule extends SkillRule implements FixableRule {
  NameFormatRule({this.severity = defaultSeverity});

  static const String ruleName = 'invalid-skill-name';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.error;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  static const maxNameLength = 64;
  static final _validNameRegex = RegExp(r'^[a-z0-9-]+$');
  static const String _skillFileName = SkillContext.skillFileName;
  static const _nameFieldUrl = 'https://agentskills.io/specification#name-field';

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];

    if (context.parsedYaml == null) {
      return errors;
    }

    final YamlMap yaml = context.parsedYaml!;
    final YamlNode? nameNode = getNameNode(yaml);
    final String skillName = nameNode?.value.toString() ?? '';

    if (skillName.isEmpty) {
      return errors; // Handled by required fields check
    }

    final SourceRegion? region = context.yamlNodeToRegion(nameNode);
    final String suggestion = suggestNormalizedName(skillName);
    final String dirName = basename(context.directory.path);

    if (skillName != dirName) {
      errors.add(
        _buildDirectoryMismatchError(skillName: skillName, dirName: dirName, region: region),
      );
    }

    if (skillName != skillName.toLowerCase()) {
      errors.add(
        _buildLowercaseError(skillName: skillName, suggestion: suggestion, region: region),
      );
    }

    if (skillName.length > maxNameLength) {
      errors.add(_buildMaxLengthError(skillName: skillName, region: region));
    }

    // Check invalid characters ignoring casing differences if casing error was already emitted
    final bool hasInvalidChars = skillName != skillName.toLowerCase()
        ? !_validNameRegex.hasMatch(skillName.toLowerCase())
        : !_validNameRegex.hasMatch(skillName);

    if (hasInvalidChars) {
      errors.add(
        _buildInvalidCharsError(skillName: skillName, suggestion: suggestion, region: region),
      );
    }

    if (skillName.startsWith('-') || skillName.endsWith('-')) {
      errors.add(
        _buildLeadingTrailingHyphensError(
          skillName: skillName,
          suggestion: suggestion,
          region: region,
        ),
      );
    }

    if (skillName.contains('--')) {
      errors.add(
        _buildConsecutiveHyphensError(skillName: skillName, suggestion: suggestion, region: region),
      );
    }

    return errors;
  }

  ValidationError _buildDirectoryMismatchError({
    required String skillName,
    required String dirName,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Frontmatter `name` "$skillName" does not match the parent '
          'directory name "$dirName". '
          'Fix by either setting `name: $dirName` in SKILL.md '
          'or renaming the directory from "$dirName" to "$skillName". '
          '(see $_nameFieldUrl)',
      markdownMessage:
          '**Frontmatter `name` does not match parent directory name.**\n\n'
          '* **Current:** `$skillName`\n'
          '* **Expected:** `$dirName`\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'name: $dirName\n'
          '```\n'
          '*Or rename the directory `$dirName` to `$skillName`.*\n\n'
          '*(See [Agent Skills Specification]($_nameFieldUrl))*',
      region: region,
    );
  }

  ValidationError _buildLowercaseError({
    required String skillName,
    required String suggestion,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Frontmatter `name` "$skillName" must be lowercase. '
          'Suggested: "$suggestion" (see $_nameFieldUrl)',
      markdownMessage:
          '**Frontmatter `name` must be lowercase.**\n\n'
          '* **Current:** `$skillName`\n'
          '* **Suggested:** `$suggestion`\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'name: $suggestion\n'
          '```\n'
          '*(See [Agent Skills Specification]($_nameFieldUrl))*',
      region: region,
    );
  }

  ValidationError _buildMaxLengthError({required String skillName, required SourceRegion? region}) {
    final int excess = skillName.length - maxNameLength;
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Frontmatter `name` is ${skillName.length} characters; '
          'maximum is $maxNameLength. '
          'Shorten the `name:` field in SKILL.md. (see $_nameFieldUrl)',
      markdownMessage:
          '**Frontmatter `name` exceeds maximum allowed length.**\n\n'
          '**${skillName.length}** characters (**$excess** characters over the **$maxNameLength** limit).\n\n'
          '**How to fix:**\n'
          'Shorten the `name:` field in `SKILL.md`.\n\n'
          '*(See [Agent Skills Specification]($_nameFieldUrl))*',
      region: region,
    );
  }

  ValidationError _buildInvalidCharsError({
    required String skillName,
    required String suggestion,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Frontmatter `name` "$skillName" contains invalid characters. '
          'Only lowercase letters, digits, and hyphens are allowed. '
          'Suggested: "$suggestion" (see $_nameFieldUrl)',
      markdownMessage:
          '**Frontmatter `name` contains invalid characters.**\n\n'
          'Only lowercase letters, digits, and hyphens are allowed.\n\n'
          '* **Current:** `$skillName`\n'
          '* **Suggested:** `$suggestion`\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'name: $suggestion\n'
          '```\n'
          '*(See [Agent Skills Specification]($_nameFieldUrl))*',
      region: region,
    );
  }

  ValidationError _buildLeadingTrailingHyphensError({
    required String skillName,
    required String suggestion,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Frontmatter `name` "$skillName" has leading or trailing hyphens. '
          'Suggested: "$suggestion" (see $_nameFieldUrl)',
      markdownMessage:
          '**Frontmatter `name` has leading or trailing hyphens.**\n\n'
          '* **Current:** `$skillName`\n'
          '* **Suggested:** `$suggestion`\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'name: $suggestion\n'
          '```\n'
          '*(See [Agent Skills Specification]($_nameFieldUrl))*',
      region: region,
    );
  }

  ValidationError _buildConsecutiveHyphensError({
    required String skillName,
    required String suggestion,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Frontmatter `name` "$skillName" has consecutive hyphens. '
          'Suggested: "$suggestion" (see $_nameFieldUrl)',
      markdownMessage:
          '**Frontmatter `name` has consecutive hyphens.**\n\n'
          '* **Current:** `$skillName`\n'
          '* **Suggested:** `$suggestion`\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'name: $suggestion\n'
          '```\n'
          '*(See [Agent Skills Specification]($_nameFieldUrl))*',
      region: region,
    );
  }

  @override
  Future<String> fix(String filePath, String currentContent, Directory directory) async {
    if (filePath != _skillFileName) {
      return currentContent;
    }

    final String dirName = basename(directory.path);
    final targetName = dirName;

    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(currentContent);
    if (match == null) {
      return currentContent;
    }

    final String frontmatter = match.group(1)!;

    // Use yaml_edit to preserve comments and formatting precisely
    try {
      final yaml = loadYaml(frontmatter) as YamlMap;
      final YamlNode? nameNode = getNameNode(yaml);
      if (nameNode == null) {
        return currentContent;
      }

      final SourceSpan span = nameNode.span;
      final String beforeName = frontmatter.substring(0, span.start.offset);
      final String afterName = frontmatter.substring(span.end.offset);

      final fixedFrontmatter = '$beforeName$targetName$afterName';
      final int yamlOffset = currentContent.indexOf(frontmatter, match.start);
      return currentContent.replaceRange(
        yamlOffset,
        yamlOffset + frontmatter.length,
        fixedFrontmatter,
      );
    } catch (_) {
      // Fallback: line-by-line replacement if AST-based replacement fails
      final List<String> lines = currentContent.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (line.trim().startsWith('name:')) {
          final String prefix = line.substring(0, line.indexOf('name:') + 5);
          lines[i] = '$prefix $targetName';
          break;
        }
      }
      return lines.join('\n');
    }
  }

  @visibleForTesting
  static YamlNode? getNameNode(YamlMap yaml) {
    for (final MapEntry<dynamic, YamlNode> entry in yaml.nodes.entries) {
      if (entry.key is YamlNode && (entry.key as YamlNode).value == 'name') {
        return entry.value;
      }
    }
    return null;
  }

  @visibleForTesting
  static bool isValidSkillName(String name) {
    if (name.isEmpty || name.length > maxNameLength) {
      return false;
    }
    return _validNameRegex.hasMatch(name);
  }

  /// Returns a best-effort normalization of [input] that conforms to the
  /// skill name format: lowercase, hyphens only, no consecutive/leading/
  /// trailing hyphens, truncated to [maxNameLength].
  ///
  /// This is intentionally a *suggestion* — the author still picks the final
  /// name. The output is not guaranteed to match a directory name.
  @visibleForTesting
  static String suggestNormalizedName(String input) => normalizeSkillNameToken(input);
}
