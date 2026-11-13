// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detector for deferred-work comments that don't link the issue that tracks
/// the work.
library;

import 'package:analyzer/dart/ast/token.dart';

import 'models/convention_violation.dart';
import 'models/source.dart';

/// Reports each comment in [source] that contains the deferred-work marker
/// but doesn't have the owner and an issue link on the same line.
///
/// A line passes when it has the marker, an owner in parentheses, a colon,
/// and then a `https://github.com/google/skills_lint.dart/issues/<n>` URL.
/// The detector doesn't check who the owner is, or that the issue exists.
List<ConventionViolation> findTodosWithoutIssue(Source source) => [
  for (final Token comment in source.comments)
    if (comment.lexeme.contains('TODO') && !_linkedTodo.hasMatch(comment.lexeme))
      source.violationAt(comment.offset, 'TODO has no issue link'),
];

final RegExp _linkedTodo = RegExp(
  r'TODO\([\w-]+\): .*https://github\.com/google/skills_lint\.dart/issues/\d+',
);
