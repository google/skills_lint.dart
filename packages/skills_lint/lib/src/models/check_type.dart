// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'analysis_severity.dart';
import 'custom_rule_parameters.dart';
import 'parameter_constraint.dart';
import 'rule_parameter_type.dart';

/// Encapsulates metadata and severity state for a specific validation rule.
class CheckType {
  const CheckType({
    required this.name,
    required this.defaultSeverity,
    required this.help,
    this.parameterSchema = const {},
    this.parameterConstraints = const {},
  });
  final String name;

  /// The default severity if not overridden by config or flags.
  final AnalysisSeverity defaultSeverity;

  /// The help message displayed by the CLI.
  final String help;

  /// Custom configuration options supported by this check.
  final Map<String, RuleParameterType> parameterSchema;

  /// Constraints on parameters in [parameterSchema], keyed by parameter name.
  ///
  /// A constraint is checked only after the value matches its
  /// [RuleParameterType].
  final Map<String, ParameterConstraint> parameterConstraints;

  /// Validates the given [parameters] against this check's [parameterSchema]
  /// and [parameterConstraints].
  ///
  /// Returns a list of error messages for any unrecognized parameters, type
  /// mismatches, or values that break a [ParameterConstraint]. Null values
  /// clear a parameter and are not checked.
  List<String> validateParameters(CustomRuleParameters parameters) {
    final List<String> errors = [];
    for (final String key in parameters.params.keys) {
      if (!parameterSchema.containsKey(key)) {
        errors.add('Unrecognized parameter "$key" for rule "$name".');
        continue;
      }
      final String? error = _validateValue(key, parameters.params[key]);
      if (error != null) {
        errors.add(error);
      }
    }
    return errors;
  }

  /// Validates only the parameters in [parameters] that declare a
  /// [ParameterConstraint], checking both their [RuleParameterType] and the
  /// constraint.
  ///
  /// Unconstrained and unrecognized parameters are ignored. CLI flags and
  /// parameters supplied through the Dart API use this so that only
  /// parameters that need validation are rejected before a rule is built.
  List<String> validateConstrainedParameters(CustomRuleParameters parameters) {
    return [
      for (final String key in parameters.params.keys)
        if (parameterConstraints.containsKey(key) && parameterSchema.containsKey(key))
          ?_validateValue(key, parameters.params[key]),
    ];
  }

  String? _validateValue(String key, Object? actualValue) {
    if (actualValue == null) {
      return null;
    }
    final RuleParameterType expectedType = parameterSchema[key]!;
    if (!expectedType.isValid(actualValue)) {
      return 'Invalid value/type for parameter "$key" in rule "$name". '
          'Expected ${expectedType.description}, got "$actualValue".';
    }
    final ParameterConstraint? constraint = parameterConstraints[key];
    if (constraint != null && !constraint.accepts(actualValue)) {
      return 'Invalid value for parameter "$key" in rule "$name". '
          'Expected ${constraint.description}, got "$actualValue".';
    }
    return null;
  }
}
