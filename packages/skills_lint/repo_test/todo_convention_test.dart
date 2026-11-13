// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/models/convention_violation.dart';
import 'src/models/source.dart';
import 'src/package_directories.dart';
import 'src/source_conventions.dart';
import 'src/todos.dart';

/// Every deferred-work comment in the repository's Dart code links the
/// google/skills_lint.dart issue that tracks the work.
///
/// Without an issue, deferred work has no place to be discussed, scheduled
/// or closed, and the comment outlives the reason for it. The
/// `flutter_style_todos` lint checks the owner and colon but not the link.
/// `checkers/todos_test.dart` pins what the detector reports.
///
/// Change this check if the repository moves its issue tracker away from
/// GitHub.
void main() {
  test('every TODO in the repository links a google/skills_lint.dart issue', () {
    final List<ConventionViolation> violations = [
      for (final Source source in parseDirectories(dartSourceDirectories))
        ...findTodosWithoutIssue(source),
    ];
    expectNoViolations(violations, fix: _fix);
  });
}

const String _fix =
    'File an issue, or do the work in this pull request. Write the TODO as '
    '`// TODO(owner): https://github.com/google/skills_lint.dart/issues/<n>`, with the '
    'link on the same line. See Deferred Work in '
    'documentation/knowledge/style_guide.md.';
