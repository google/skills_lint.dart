// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// A restriction on the value of a rule parameter, beyond its
/// `RuleParameterType`.
///
/// Mirrors `RuleParameterType`: [accepts] tests a value and [description]
/// names the accepted values for error messages. Register constraints in
/// `CheckType.parameterConstraints`. The configuration file, CLI flags, and
/// `RuleRegistry.createRule` all validate through `CheckType`, so a rule does
/// not need to check its own parameter values.
@immutable
class ParameterConstraint {
  const ParameterConstraint({required this.description, required this._accepts});

  /// Describes the accepted values, such as `a positive integer`.
  final String description;

  final bool Function(Object value) _accepts;

  /// Whether [value] meets this constraint.
  ///
  /// `CheckType` calls this only for values that match the parameter's
  /// `RuleParameterType`.
  bool accepts(Object value) => _accepts(value);
}
