// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';
import '../cutoff_excerpt.dart';
import '../length_limit.dart';
import '../models/analysis_severity.dart';
import '../models/parameter_constraint.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import 'valid_yaml_metadata_rule.dart';

/// Enforces that the description field is not too long.
///
/// The limit defaults to [maxDescriptionLength], the maximum set by the
/// Agent Skills specification ([_descriptionFieldUrl]). Repositories can set
/// a longer or shorter limit with the [maxDescriptionLengthParameter] rule
/// parameter.
class DescriptionLengthRule extends SkillRule {
  DescriptionLengthRule({this.severity = defaultSeverity, this.maxLength = maxDescriptionLength});

  static const String ruleName = 'description-too-long';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.error;

  /// The rule parameter that sets the maximum description length in characters.
  static const String maxDescriptionLengthParameter = 'description-length-max';

  /// Restricts [maxDescriptionLengthParameter] to integers of at least 1.
  static const maxDescriptionLengthConstraint = ParameterConstraint(
    description: 'a positive integer',
    accepts: _isPositiveInteger,
  );

  /// The maximum description length set by the Agent Skills specification.
  static const maxDescriptionLength = 1024;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  /// The maximum number of characters allowed in the description field.
  @visibleForTesting
  final int maxLength;

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

    if (description.length > maxLength) {
      final SourceRegion? region = context.yamlNodeToRegion(descNode);
      errors.add(
        ValidationError(
          ruleId: name,
          severity: severity,
          file: _skillFileName,
          message: buildLengthDiagnostic(
            fieldName: 'Description',
            value: description,
            limit: LengthLimit(maxLength: maxLength, specMaxLength: maxDescriptionLength),
            docUrl: _descriptionFieldUrl,
          ),
          markdownMessage: buildLengthMarkdownDiagnostic(
            fieldName: 'description',
            value: description,
            limit: LengthLimit(maxLength: maxLength, specMaxLength: maxDescriptionLength),
            docUrl: _descriptionFieldUrl,
          ),
          region: region,
        ),
      );
    }

    return errors;
  }
}

bool _isPositiveInteger(Object value) => value is int && value >= 1;
