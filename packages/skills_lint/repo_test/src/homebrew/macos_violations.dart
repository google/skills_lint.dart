// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../models/convention_violation.dart';
import 'formula_value.dart';
import 'homebrew_formula.dart';

/// The major version of each macOS that `depends_on macos:` can name.
///
/// Add the next macOS here when `macosMinimumVersion` in
/// `release/lib/src/macho.dart` moves to it.
const Map<String, int> macosSymbolMajors = {
  'ventura': 13,
  'sonoma': 14,
  'sequoia': 15,
  'tahoe': 26,
};

/// Reports where the `depends_on macos:` of [formula] is missing, outside
/// `on_macos`, or names another macOS than [minimumVersion], the minimum
/// macOS version of the executables.
///
/// Homebrew names major versions only, so [minimumVersion] must be
/// `<major>.0`. A null [minimumVersion] skips that comparison.
List<ConventionViolation> findMacosViolations(
  String path,
  HomebrewFormula formula,
  String? minimumVersion,
) {
  final FormulaValue? dependency = formula.macosMinimum;
  if (dependency == null) {
    return [
      ConventionViolation(path, missingStatementLine, 'has no depends_on macos: inside on_macos'),
    ];
  }
  final List<ConventionViolation> violations = [];
  if (!formula.macosMinimumOnMacosOnly) {
    violations.add(
      ConventionViolation(
        path,
        dependency.line,
        'depends_on macos: is outside on_macos, so Linux cannot install',
      ),
    );
  }
  final String symbol = dependency.value;
  final int? major = macosSymbolMajors[symbol];
  if (major == null) {
    violations.add(
      ConventionViolation(path, dependency.line, ':$symbol is not in macosSymbolMajors'),
    );
  } else if (minimumVersion != null && '$major.0' != minimumVersion) {
    violations.add(
      ConventionViolation(
        path,
        dependency.line,
        ':$symbol is macOS $major.0, but the executables need macOS $minimumVersion',
      ),
    );
  }
  return violations;
}
