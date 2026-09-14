// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import '../config_serializer.dart';
import 'analysis_severity.dart';
import 'custom_rule_parameters.dart';

/// Represents the resolved, active configuration for a validation rule,
/// bundling both orchestration (severity) and execution parameters.
@immutable
class RuleConfig {
  const RuleConfig({required this.severity, CustomRuleParameters? parameters})
    : parameters = parameters ?? const CustomRuleParameters.empty();

  /// The active analysis severity for this rule.
  final AnalysisSeverity severity;

  /// The resolved custom parameters for this rule.
  final CustomRuleParameters parameters;

  /// Converts this rule configuration into its YAML representation (String severity or Map).
  Object toYaml() => ConfigSerializer.ruleConfigToYaml(this);

  /// Converts this rule configuration into its YAML map representation.
  Map<String, Object?> toYamlMap() => ConfigSerializer.ruleConfigToYamlMap(this);

  /// Converts this rule configuration into a formatted YAML string.
  String toYamlString() => ConfigSerializer.toYamlString(this);

  /// Converts this resolved rule configuration into a corresponding [RuleConfigPatch].
  RuleConfigPatch toPatch() => RuleConfigPatch(severity: severity, parameters: parameters);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RuleConfig &&
            runtimeType == other.runtimeType &&
            severity == other.severity &&
            parameters == other.parameters;
  }

  @override
  int get hashCode => Object.hash(severity, parameters);

  @override
  String toString() => 'RuleConfig(severity: $severity, parameters: $parameters)';
}

/// Represents a configuration override patch containing nullable parameters.
/// Used during validation session configuration inheritance to resolve target-specific
/// overrides without wiping out unspecified base/global parameters.
@immutable
class RuleConfigPatch {
  const RuleConfigPatch({this.severity, this.parameters});

  /// The overridden severity value. If null, the base configuration's severity is preserved.
  final AnalysisSeverity? severity;

  /// The overridden parameters. Keys containing null values (e.g. from YAML `~`) will remove
  /// the parameter from the base configuration during merging.
  final CustomRuleParameters? parameters;

  /// Converts this rule configuration patch into its YAML representation (String severity or Map).
  Object? toYaml() => ConfigSerializer.ruleConfigPatchToYaml(this);

  /// Converts this rule configuration patch into its YAML map representation.
  Map<String, Object?> toYamlMap() => ConfigSerializer.ruleConfigPatchToYamlMap(this);

  /// Converts this rule configuration patch into a formatted YAML string.
  String toYamlString() => ConfigSerializer.toYamlString(this);

  /// Creates a new [RuleConfig] by layering this patch's overrides over a [base] configuration.
  RuleConfig applyTo(RuleConfig base) {
    return RuleConfig(
      severity: severity ?? base.severity,
      parameters: parameters != null
          ? _mergeParameters(base.parameters, parameters!)
          : base.parameters,
    );
  }

  static CustomRuleParameters _mergeParameters(
    CustomRuleParameters base,
    CustomRuleParameters patch,
  ) {
    final merged = Map<String, Object?>.from(base.params);
    for (final MapEntry<String, Object?> entry in patch.params.entries) {
      if (entry.value == null) {
        merged.remove(entry.key);
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return CustomRuleParameters(merged);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RuleConfigPatch &&
            runtimeType == other.runtimeType &&
            severity == other.severity &&
            parameters == other.parameters;
  }

  @override
  int get hashCode => Object.hash(severity, parameters);

  @override
  String toString() => 'RuleConfigPatch(severity: $severity, parameters: $parameters)';
}
