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
  const RuleConfig({required this.severity, CustomRuleParameters? parameters, bool? fix})
    : parameters = parameters ?? const CustomRuleParameters.empty(),
      fix = fix ?? defaultFix;

  final AnalysisSeverity severity;
  final CustomRuleParameters parameters;

  /// Whether `--fix` may run this rule's fix. See `WritePolicy` for how it
  /// combines with where a fix may write.
  final bool fix;

  /// The value of [fix] when no configuration sets it.
  static const bool defaultFix = true;

  /// Converts this rule configuration into its YAML representation (String severity or Map).
  Object toYaml() {
    if (parameters.isEmpty && fix == defaultFix) {
      return severity.name;
    }
    return <String, Object?>{
      ConfigParser.severityKey: severity.name,
      if (fix != defaultFix) ConfigParser.fixKey: fix,
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
  const RuleConfigPatch({this.severity, this.parameters, this.fix});

  /// The overridden severity value. If null, the base configuration's severity is preserved.
  final AnalysisSeverity? severity;

  /// The overridden parameters. Keys containing null values (e.g. from YAML `~`) will remove
  /// the parameter from the base configuration during merging.
  final CustomRuleParameters? parameters;

  /// The overridden [RuleConfig.fix]. If null, the base configuration's value
  /// is preserved.
  final bool? fix;

  /// Converts this rule configuration patch into its YAML representation (String severity or Map).
  Object? toYaml() {
    final CustomRuleParameters? params = parameters;
    if ((params == null || params.isEmpty) && fix == null) {
      return severity?.name ?? <String, Object?>{};
    }
    return <String, Object?>{
      if (severity != null) ConfigParser.severityKey: severity!.name,
      if (fix != null) ConfigParser.fixKey: fix,
      for (final MapEntry<String, Object?> entry
          in params?.params.entries ?? const <MapEntry<String, Object?>>[])
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
      fix: fix ?? base.fix,
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
