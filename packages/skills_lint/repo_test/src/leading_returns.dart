// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/token.dart';

import 'models/convention_violation.dart';
import 'models/source.dart';

final RegExp _leadingReturns = RegExp(r'^///\s*Returns\b');

/// Reports each `///` block whose first line starts with "Returns".
///
/// The style guide's "No leading Returns" rule asks for a noun phrase or a
/// third-person verb that says what the member does. Only the first line of
/// a block is checked, so a later paragraph may still start with "Returns".
/// `/** */` comments are not checked.
List<ConventionViolation> findLeadingReturns(Source source) {
  final List<ConventionViolation> violations = [];
  Token? previous;
  for (final Token comment in source.comments) {
    if (_isDocLine(comment) && !_continuesBlock(source, previous, comment)) {
      if (_leadingReturns.hasMatch(comment.lexeme)) {
        violations.add(source.violationAt(comment.offset, 'doc comment starts with "Returns"'));
      }
    }
    previous = comment;
  }
  return violations;
}

/// Whether [comment] is a `///` doc line. A `////` line is a plain comment.
bool _isDocLine(Token comment) =>
    comment.lexeme.startsWith('///') && !comment.lexeme.startsWith('////');

/// Whether [comment] is the next line of the `///` block that [previous]
/// belongs to.
bool _continuesBlock(Source source, Token? previous, Token comment) {
  if (previous == null || !_isDocLine(previous)) {
    return false;
  }
  final String between = source.content.substring(previous.end, comment.offset);
  return between.trim().isEmpty && '\n'.allMatches(between).length == 1;
}
