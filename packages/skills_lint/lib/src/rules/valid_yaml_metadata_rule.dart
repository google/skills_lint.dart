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

/// Enforces that SKILL.md has valid YAML frontmatter and required fields.
class ValidYamlMetadataRule extends SkillRule {
  ValidYamlMetadataRule({this.severity = defaultSeverity});

  static const String ruleName = 'valid-yaml-metadata';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.error;

  /// Frontmatter field key for name.
  static const String keyName = 'name';

  /// Frontmatter field key for description.
  static const String keyDescription = 'description';

  /// Frontmatter field key for compatibility.
  static const String keyCompatibility = 'compatibility';

  /// Frontmatter field key for metadata.
  static const String keyMetadata = 'metadata';

  /// Metadata subfield key for internal flag.
  static const String keyInternal = 'internal';

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  static const Set<String> _requiredFields = {keyName, keyDescription};
  static const String _skillFileName = 'SKILL.md';
  static const String _metadataUrl = 'https://agentskills.io/specification#frontmatter';
  static const int maxCompatibilityLength = 500;
  static const String _compatibilityFieldUrl =
      'https://agentskills.io/specification#compatibility-field';

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];

    if (context.parsedYaml == null) {
      errors.add(
        ValidationError(
          ruleId: name,
          severity: severity,
          file: _skillFileName,
          message:
              'Invalid YAML metadata: ${context.yamlParsingError ?? 'Missing or invalid'} (see $_metadataUrl)',
          // When frontmatter is absent or malformed, the error applies
          // to the entire file rather than a specific line or node.
          region: SourceRegion.wholeFile,
        ),
      );
      return errors;
    }

    final YamlMap yaml = context.parsedYaml!;
    for (final String field in _requiredFields) {
      if (!yaml.containsKey(field)) {
        errors.add(
          ValidationError(
            ruleId: name,
            severity: severity,
            file: _skillFileName,
            message: 'Missing required field: $field (see $_metadataUrl)',
            // When a required frontmatter field is absent, no AST node exists to
            // anchor a line/column coordinate. Whole-file scope indicates the
            // file is missing top-level structure.
            region: SourceRegion.wholeFile,
          ),
        );
      }
    }

    if (yaml.containsKey(keyCompatibility)) {
      final String compatibility = yaml[keyCompatibility]?.toString() ?? '';
      if (compatibility.length > maxCompatibilityLength) {
        final YamlNode? compatNode = yaml.nodes[keyCompatibility];
        final SourceRegion? region = context.yamlNodeToRegion(compatNode);
        errors.add(
          ValidationError(
            ruleId: name,
            severity: severity,
            file: _skillFileName,
            message: buildLengthDiagnostic(
              fieldName: 'Compatibility',
              value: compatibility,
              maxLength: maxCompatibilityLength,
              docUrl: _compatibilityFieldUrl,
            ),
            region: region,
          ),
        );
      }
    }

    return errors;
  }
}
