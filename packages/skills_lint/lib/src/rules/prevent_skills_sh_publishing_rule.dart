// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import 'valid_yaml_metadata_rule.dart';

/// Enforces that skills are marked as internal to prevent accidental publishing to the public skills.sh registry.
/// This rule requires `metadata.internal` to be explicitly set to `true` in the SKILL.md YAML frontmatter.
class PreventSkillsShPublishingRule extends SkillRule {
  PreventSkillsShPublishingRule({this.severity = defaultSeverity});

  static const String ruleName = 'prevent-skills-sh-publishing';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  static const String _skillFileName = 'SKILL.md';

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];

    if (context.yamlParsingError != null) {
      return errors;
    }

    if (context.parsedYaml == null) {
      errors.add(_buildMissingFrontmatterError());
      return errors;
    }

    final YamlMap yaml = context.parsedYaml!;
    final Object? metadata = yaml[ValidYamlMetadataRule.keyMetadata];

    if (metadata == null) {
      errors.add(_buildMissingMetadataBlockError());
      return errors;
    }

    if (metadata is! YamlMap) {
      final YamlNode? metadataNode = yaml.nodes[ValidYamlMetadataRule.keyMetadata];
      errors.add(_buildMetadataNotMapError(context.yamlNodeToRegion(metadataNode)));
      return errors;
    }

    final YamlMap metadataMap = metadata;
    final Object? internalVal = metadataMap[ValidYamlMetadataRule.keyInternal];

    if (internalVal is String) {
      final YamlNode? internalNode = metadataMap.nodes[ValidYamlMetadataRule.keyInternal];
      errors.add(
        _buildStringBooleanError(
          stringValue: internalVal,
          region: context.yamlNodeToRegion(internalNode),
        ),
      );
      return errors;
    }

    if (internalVal != true) {
      final YamlNode? targetNode =
          metadataMap.nodes[ValidYamlMetadataRule.keyInternal] ??
          yaml.nodes[ValidYamlMetadataRule.keyMetadata];
      errors.add(_buildInternalNotTrueError(region: context.yamlNodeToRegion(targetNode)));
    }

    return errors;
  }

  ValidationError _buildMissingFrontmatterError() {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Missing YAML frontmatter. Expected:\n'
          'metadata:\n'
          '  internal: true',
      markdownMessage:
          '**Missing YAML frontmatter.**\n\n'
          'To prevent accidental publishing to public registries, mark the skill as internal.\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'metadata:\n'
          '  internal: true\n'
          '```',
      region: SourceRegion.wholeFile,
    );
  }

  ValidationError _buildMissingMetadataBlockError() {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'Missing "metadata" block in YAML frontmatter. Expected:\n'
          'metadata:\n'
          '  internal: true',
      markdownMessage:
          '**Missing `metadata` block in YAML frontmatter.**\n\n'
          'To prevent accidental publishing to public registries, mark the skill as internal.\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'metadata:\n'
          '  internal: true\n'
          '```',
      region: SourceRegion.wholeFile,
    );
  }

  ValidationError _buildMetadataNotMapError(SourceRegion? region) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          '"metadata" must be a YAML mapping (dictionary). Expected:\n'
          'metadata:\n'
          '  internal: true',
      markdownMessage:
          '**`metadata` must be a YAML mapping (dictionary).**\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'metadata:\n'
          '  internal: true\n'
          '```',
      region: region,
    );
  }

  ValidationError _buildStringBooleanError({
    required String stringValue,
    required SourceRegion? region,
  }) {
    final String trimmedLower = stringValue.trim().toLowerCase();
    final fixExplanation = trimmedLower == 'true'
        ? 'Remove quotes around `true` so it parses as a boolean:'
        : 'Set `metadata.internal` to boolean `true` without quotes:';

    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'The "internal" field under "metadata" is set to a string "$stringValue". '
          'Please remove quotes and set to boolean true.',
      markdownMessage:
          '**`metadata.internal` must be a boolean.**\n\n'
          'The field is set to a string `"$stringValue"`.\n\n'
          '**How to fix:**\n'
          '$fixExplanation\n'
          '```yaml\n'
          'metadata:\n'
          '  internal: true\n'
          '```',
      region: region,
    );
  }

  ValidationError _buildInternalNotTrueError({required SourceRegion? region}) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: _skillFileName,
      message:
          'The "internal" field under "metadata" must be explicitly set to boolean true to prevent accidental publishing. Expected:\n'
          'metadata:\n'
          '  internal: true',
      markdownMessage:
          '**`metadata.internal` must be set to `true`.**\n\n'
          'To prevent accidental publishing to public registries, mark the skill as internal.\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'metadata:\n'
          '  internal: true\n'
          '```',
      region: region,
    );
  }
}
