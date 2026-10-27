// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import '../config_parser.dart';
import '../config_serializer.dart';
import 'analysis_severity.dart';
import 'custom_rule_parameters.dart';

/// Represents the resolved, active configuration for a validation rule,
/// bundling both orchestration (severity) and execution parameters.
@immutable
class RuleConfig {
  const RuleConfig({required this.severity, CustomRuleParameters? parameters})
    : parameters = parameters ?? const CustomRuleParameters.empty();

  final AnalysisSeverity severity;
  final CustomRuleParameters parameters;

  /// Converts this rule configuration into its YAML representation (String severity or Map).
  Object toYaml() {
    if (parameters.isEmpty) {
      return severity.name;
    }
    return <String, Object?>{
      ConfigParser.severityKey: severity.name,
      for (final MapEntry<String, Object?> entry in parameters.params.entries)
        if (entry.key != ConfigParser.severityKey) entry.key: entry.value,
    };
  }

  /// Converts this rule configuration into a formatted YAML string.
  String toYamlString() => ConfigSerializer.toYamlString(toYaml());
}

/// Represents a configuration override patch containing nullable parameters.
/// Used during validation session configuration inheritance to resolve target-specific
/// overrides without wiping out unspecified base/global parameters.
@immutable
class RuleConfigPatch {
  const RuleConfigPatch({this.severity, this.parameters}) : _line = null;

  /// Builds a patch that remembers the 1-based line on which its rule key
  /// appeared in a configuration file.
  const RuleConfigPatch._parsed({this.severity, this.parameters, required int this._line});

  /// The overridden severity value. If null, the base configuration's severity is preserved.
  final AnalysisSeverity? severity;

  /// The overridden parameters. Keys containing null values (e.g. from YAML `~`) will remove
  /// the parameter from the base configuration during merging.
  final CustomRuleParameters? parameters;

  final int? _line;

  /// Converts this rule configuration patch into its YAML representation (String severity or Map).
  Object? toYaml() {
    final CustomRuleParameters? params = parameters;
    if (params == null || params.isEmpty) {
      return severity?.name ?? <String, Object?>{};
    }
    return <String, Object?>{
      if (severity != null) ConfigParser.severityKey: severity!.name,
      for (final MapEntry<String, Object?> entry in params.params.entries)
        if (entry.key != ConfigParser.severityKey) entry.key: entry.value,
    };
  }

  /// Converts this rule configuration patch into a formatted YAML string.
  String toYamlString() => ConfigSerializer.toYamlString(toYaml());

  /// Creates a [RuleConfig] by layering this patch's overrides over a [base] configuration.
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
}

/// Creates a [RuleConfigPatch] that records the 1-based [line] where its rule
/// key was parsed.
///
/// Internal to skills_lint: `package:skills_lint/skills_lint.dart` hides this
/// function.
RuleConfigPatch parsedRuleConfigPatch({
  AnalysisSeverity? severity,
  CustomRuleParameters? parameters,
  required int line,
}) => RuleConfigPatch._parsed(severity: severity, parameters: parameters, line: line);

/// Reads the 1-based line on which [patch]'s rule key was declared, or `null`
/// for a patch built directly by a caller.
///
/// Internal to skills_lint: `package:skills_lint/skills_lint.dart` hides this
/// function.
int? ruleLineOf(RuleConfigPatch patch) => patch._line;
