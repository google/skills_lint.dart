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
///
/// The limit defaults to [maxDescriptionLength], the maximum set by the
/// Agent Skills specification. Repositories can set a stricter or looser
/// limit with the [charsParameter] rule parameter. A limit below
/// [maxDescriptionLength] is a repository policy rather than a specification
/// requirement, so its diagnostic reports a configured maximum and omits the
/// specification link.
class DescriptionLengthRule extends SkillRule {
  /// Creates the rule.
  ///
  /// Throws an [ArgumentError] if [maxChars] is less than 1.
  DescriptionLengthRule({this.severity = defaultSeverity, this.maxChars = defaultMaxChars}) {
    if (maxChars < 1) {
      throw ArgumentError.value(maxChars, 'maxChars', 'must be a positive integer');
    }
  }

  static const String ruleName = 'description-too-long';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.error;

  /// The rule parameter that sets the maximum description length in characters.
  static const String charsParameter = 'chars';

  /// The maximum description length set by the Agent Skills specification.
  static const maxDescriptionLength = 1024;

  /// The limit applied when [charsParameter] is not configured.
  static const int defaultMaxChars = maxDescriptionLength;

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  /// The maximum number of characters allowed in the description field.
  final int maxChars;

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

    if (description.length > maxChars) {
      final SourceRegion? region = context.yamlNodeToRegion(descNode);
      errors.add(
        ValidationError(
          ruleId: name,
          severity: severity,
          file: _skillFileName,
          message: buildLengthDiagnostic(
            fieldName: 'Description',
            value: description,
            maxLength: maxChars,
            docUrl: _docUrl,
            isConfiguredLimit: _isConfiguredLimit,
          ),
          markdownMessage: buildLengthMarkdownDiagnostic(
            fieldName: 'description',
            value: description,
            maxLength: maxChars,
            docUrl: _docUrl,
            isConfiguredLimit: _isConfiguredLimit,
          ),
          region: region,
        ),
      );
    }

    return errors;
  }

  /// Whether [maxChars] is a repository policy stricter than the specification.
  bool get _isConfiguredLimit => maxChars < maxDescriptionLength;

  /// The specification link, omitted when the limit is a repository policy.
  String? get _docUrl => _isConfiguredLimit ? null : _descriptionFieldUrl;
}
