// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks the value of a rule parameter after it has matched its
/// `RuleParameterType`.
///
/// Returns `null` when [value] is accepted. Otherwise returns a short
/// description of the accepted values, such as `a positive integer`, which
/// `CheckType.validateParameters` places in its error message.
///
/// Register checks in `CheckType.parameterValueChecks`. The configuration
/// file, CLI flags, and `RuleRegistry.createRule` all validate through
/// `CheckType.validateParameters`, so a rule does not need to check its own
/// parameter values.
typedef ParameterValueCheck = String? Function(Object value);

/// Accepts integers greater than or equal to 1.
String? requirePositiveInteger(Object value) =>
    value is int && value >= 1 ? null : 'a positive integer';
