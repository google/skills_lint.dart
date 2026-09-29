// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// One repo-convention finding: where it is and what is wrong.
class ConventionViolation {
  ConventionViolation(this.path, this.line, this.problem);

  final String path;

  /// 1-based line of the offending code.
  final int line;
  final String problem;

  String describe() => '$path:$line: $problem';
}
