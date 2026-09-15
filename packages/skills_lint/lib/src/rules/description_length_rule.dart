// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';
import '../cutoff_excerpt.dart';
import '../models/analysis_severity.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import 'valid_yaml_metadata_rule.dart';

/// Enforces that the description field is not too long.
class DescriptionLengthRule extends SkillRule {
  DescriptionLengthRule({this.severity = defaultSeverity});

  static const String ruleName = 'description-too-long';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.error;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  static const maxDescriptionLength = 1024;
  static const _skillFileName = 'SKILL.md';
  static const _descriptionFieldUrl = 'https://agentskills.io/specification#description-field';

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];

    if (context.parsedYaml == null) {
      return errors;
    }

    final YamlMap yaml = context.parsedYaml!;
    final YamlNode? descNode = yaml.nodes[ValidYamlMetadataRule.keyDescription];
    final String description = descNode?.value?.toString() ?? '';

    if (description.length > maxDescriptionLength) {
      final SourceRegion? region = context.yamlNodeToRegion(descNode);
      errors.add(
        ValidationError(
          ruleId: name,
          severity: severity,
          file: _skillFileName,
          message: buildLengthDiagnostic(
            fieldName: 'Description',
            value: description,
            maxLength: maxDescriptionLength,
            docUrl: _descriptionFieldUrl,
          ),
          markdownMessage: buildLengthMarkdownDiagnostic(
            fieldName: 'description',
            value: description,
            maxLength: maxDescriptionLength,
            docUrl: _descriptionFieldUrl,
          ),
          region: region,
        ),
      );
    }

    return errors;
  }
}
