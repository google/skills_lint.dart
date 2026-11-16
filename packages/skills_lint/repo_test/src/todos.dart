// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detector for deferred-work comments that don't link the issue that tracks
/// the work.
library;

import 'package:analyzer/dart/ast/token.dart';

import 'models/convention_violation.dart';
import 'models/source.dart';

/// Reports each deferred-work comment in [source] that lacks an owner in
/// parentheses followed on the same line by `#<n>` or a GitHub issue URL.
List<ConventionViolation> findTodosWithoutIssue(Source source) => [
  for (final Token comment in source.comments)
    if (comment.lexeme.contains('TODO') && !_linkedTodo.hasMatch(comment.lexeme))
      source.violationAt(comment.offset, 'TODO has no issue link'),
];

final RegExp _linkedTodo = RegExp(
  r'TODO\([\w-]+\): .*(?:\B#\d+\b|https://github\.com/[\w.-]+/[\w.-]+/issues/\d+)',
);
