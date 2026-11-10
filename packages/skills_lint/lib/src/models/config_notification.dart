// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'analysis_severity.dart';
import 'config_location.dart';
import 'config_problem.dart';

/// A problem with the configuration skills_lint ran with, such as an entry in
/// `skills_lint.yaml` or an ignore file that it could not use.
///
/// Reports list these apart from the findings about skills.
@immutable
class ConfigNotification {
  const ConfigNotification({
    required this.severity,
    required this.message,
    this.file,
    this.position,
  });

  /// A notification for [problem], whose location gives [file] and
  /// [position].
  ConfigNotification.fromProblem(ConfigProblem problem, {required this.severity})
    : message = problem.message,
      file = problem.location?.file,
      position = switch (problem.location) {
        null => null,
        final ConfigLocation location => (line: location.line, column: location.column),
      };

  /// [AnalysisSeverity.error] when the problem stopped skills_lint from
  /// running, and [AnalysisSeverity.warning] when skills_lint ran without the
  /// entry.
  final AnalysisSeverity severity;

  /// What is wrong.
  final String message;

  /// The configuration or ignore file, or `null` when the configuration did
  /// not come from a file.
  final String? file;

  /// The 1-based line and column in [file], or `null` when the problem is
  /// about the whole file.
  final ({int line, int column})? position;
}
