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
  static const _nameFieldUrl = 'https://agentskills.io/specification#name-field';

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];

    if (context.parsedYaml == null) {
      return errors;
    }

    final YamlMap yaml = context.parsedYaml!;
    final YamlNode? nameNode = getNameNode(yaml);
    final String skillName = nameText(nameNode) ?? '';

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

    if (_hasEdgeHyphen(skillName)) {
      errors.add(
        _buildLeadingTrailingHyphensError(
          skillName: skillName,
          suggestion: suggestion,
          region: region,
        ),
      );
    }

    if (_hasConsecutiveHyphens(skillName)) {
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
      file: SkillContext.skillFileName,
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
      file: SkillContext.skillFileName,
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
      file: SkillContext.skillFileName,
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
      file: SkillContext.skillFileName,
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
      file: SkillContext.skillFileName,
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
      file: SkillContext.skillFileName,
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
    if (filePath != SkillContext.skillFileName) {
      return currentContent;
    }

    final String targetName = basename(directory.path);
    if (!isValidSkillName(targetName)) {
      return currentContent;
    }

    final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(currentContent);
    if (match == null) {
      return currentContent;
    }

    final String frontmatter = match.group(1)!;

    final Object? yaml;
    try {
      yaml = loadYaml(frontmatter);
    } on YamlException {
      // Malformed frontmatter has no name node to rewrite. The validator
      // reports the YAML error, so leave the content unchanged.
      return currentContent;
    }
    if (yaml is! YamlMap) {
      return currentContent;
    }

    // Replace the name node span while preserving comments and formatting precisely
    final YamlNode? nameNode = getNameNode(yaml);
    if (nameNode == null ||
        nameNode is! YamlScalar ||
        nameNode.value == null ||
        nameNode.value.toString().trim().isEmpty) {
      return currentContent;
    }

    final SourceSpan span = nameNode.span;
    final String beforeName = frontmatter.substring(0, span.start.offset);
    final String afterName = frontmatter.substring(span.end.offset);

    // Unquoted, YAML reads some valid names as another type: `123` as a
    // number, `false` as a boolean. Valid names hold only letters, digits and
    // hyphens, so they never need escaping, and loadYaml parses any of them.
    final String quote = switch (nameNode.style) {
      ScalarStyle.SINGLE_QUOTED => "'",
      ScalarStyle.DOUBLE_QUOTED => '"',
      _ => loadYaml(targetName) == targetName ? '' : '"',
    };
    final fixedFrontmatter = '$beforeName$quote$targetName$quote$afterName';
    final int yamlOffset = currentContent.indexOf(frontmatter, match.start);
    return currentContent.replaceRange(
      yamlOffset,
      yamlOffset + frontmatter.length,
      fixedFrontmatter,
    );
  }

  /// Returns the value node of the `name` key in [yaml], or `null` if there
  /// is none.
  static YamlNode? getNameNode(YamlMap yaml) {
    for (final MapEntry<dynamic, YamlNode> entry in yaml.nodes.entries) {
      if (entry.key is YamlNode && (entry.key as YamlNode).value == 'name') {
        return entry.value;
      }
    }
    return null;
  }

  /// Gets the skill name from [node], the value of the `name` key, as text,
  /// or `null` if there is no name, as in `name:`.
  ///
  /// Compare names with this rather than with `node.value`: for `name: 1e3`
  /// it gives `1e3`, where `node.value` is the number `1000.0`.
  static String? nameText(YamlNode? node) => switch (node) {
    YamlScalar(value: final String name) => name,
    YamlScalar(value: null) => null,
    // The spec defines a name as text, so read a number or boolean from the
    // source as written. A scalar that ends the document spans its trailing
    // spaces, hence the trim.
    YamlScalar(:final SourceSpan span) => span.text.trim(),
    _ => node?.value?.toString(),
  };

  /// Whether [name] is a valid skill name: lowercase ASCII letters, digits
  /// and hyphens, from 1 to [maxNameLength] characters, with no leading,
  /// trailing or consecutive hyphens.
  ///
  /// A non-empty name passes the format checks in [validate] exactly when
  /// this returns true.
  static bool isValidSkillName(String name) {
    if (name.isEmpty || name.length > maxNameLength) {
      return false;
    }
    return _validNameRegex.hasMatch(name) && !_hasEdgeHyphen(name) && !_hasConsecutiveHyphens(name);
  }

  static bool _hasEdgeHyphen(String name) => name.startsWith('-') || name.endsWith('-');

  static bool _hasConsecutiveHyphens(String name) => name.contains('--');

  /// Returns a best-effort normalization of [input] that conforms to the
  /// skill name format: lowercase, hyphens only, no consecutive/leading/
  /// trailing hyphens, truncated to [maxNameLength].
  ///
  /// This is intentionally a *suggestion* — the author still picks the final
  /// name. The output is not guaranteed to match a directory name.
  @visibleForTesting
  static String suggestNormalizedName(String input) => normalizeSkillNameToken(input);
}
