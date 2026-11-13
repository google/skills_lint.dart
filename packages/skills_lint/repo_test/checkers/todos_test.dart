// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/models/convention_violation.dart';
import '../src/models/source.dart';
import '../src/todos.dart';

/// Runs [findTodosWithoutIssue] over small inline snippets, which pins what
/// it reports independently of the package's code.
void main() {
  group('findTodosWithoutIssue', () {
    test('accepts a TODO with an owner and an issue link on the same line', () {
      final source = Source.snippet('''
// TODO(reidbaker): #75
// TODO(reidbaker): Remove the flag in 0.6.0 (#73).
// TODO(reidbaker): https://github.com/flutter/flutter/issues/12345
// TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/75
// TODO(reidbaker-agent): Remove the flag in 0.6.0. https://github.com/google/skills_lint.dart/issues/73
/// TODO(Vaishnavi220506): https://github.com/google/skills_lint.dart/issues/71 - remove sourcePath.
void main() {}
''');
      expect(findTodosWithoutIssue(source), isEmpty);
    });

    test('ignores comments without TODO and TODO in a string', () {
      final source = Source.snippet('''
// Remove the flag in 0.6.0.
void main() {
  print('TODO: write the report');
}
''');
      expect(findTodosWithoutIssue(source), isEmpty);
    });

    test('reports a TODO with no link, a number not marked as an issue, or no owner', () {
      final source = Source.snippet('''
// TODO(reidbaker): Remove the flag on the next major version bump.
// TODO(reidbaker): Remove the flag in 0.6.0, see issue 73.
// TODO(reidbaker): Fix the parser#73 path.
// TODO(reidbaker): https://github.com/flutter/flutter/pull/12345
// TODO: #75
// TODO fix this
/* TODO(reidbaker): handle Windows paths. */
void main() {}
''');
      final List<ConventionViolation> violations = findTodosWithoutIssue(source);
      expect(_lines(violations), [1, 2, 3, 4, 5, 6, 7]);
      expect(violations.first.describe(), 'lib/snippet.dart:1: TODO has no issue link');
    });

    test('reports a TODO whose issue link is on the next line', () {
      final source = Source.snippet('''
void main() {
  // TODO(reidbaker): Remove sourcePath in 0.6.0.
  // #71
}
''');
      expect(_lines(findTodosWithoutIssue(source)), [2]);
    });
  });
}

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
