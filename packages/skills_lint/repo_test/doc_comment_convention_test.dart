// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/leading_returns.dart';
import 'src/models/convention_violation.dart';
import 'src/models/source.dart';
import 'src/source_conventions.dart';

/// Checks the style guide's "No leading Returns" rule: no `///` block's first
/// line starts with "Returns".
///
/// Effective Dart allows a leading "Returns", but this repo asks for a noun
/// phrase or a third-person verb so the summary says what a member is or
/// does. A later paragraph may still start with "Returns". Only `lib/`,
/// `release/lib/` and `repo_test/` are scanned, the code reviewers read most;
/// `third_party/` is vendored and keeps its upstream wording. Widen the scope
/// or drop the rule if the style guide's bullet changes.
///
/// `leading_returns_test.dart` in `checkers/` pins what the detector reports.
void main() {
  late List<Source> sources;

  setUpAll(() {
    sources = parseDirectories(
      _scannedDirectories,
    ).where((source) => !source.path.contains('third_party/')).toList();
  });

  test('no doc comment starts with "Returns"', () {
    final List<ConventionViolation> violations = [
      for (final Source source in sources)
        if (!_shouldBeFixed.contains(source.path)) ...findLeadingReturns(source),
    ];
    expectNoViolations(violations, fix: _fix);
  });

  test('every file in the allowlist still has a leading "Returns"', () {
    final List<String> clean = [
      for (final String path in _shouldBeFixed)
        if (findLeadingReturns(sources.firstWhere((s) => s.path == path)).isEmpty) path,
    ];
    expect(
      clean,
      isEmpty,
      reason:
          '${clean.join(', ')} no longer has a leading "Returns"; remove it from the allowlist.',
    );
  });
}

const List<String> _scannedDirectories = ['lib', '../../release/lib', 'repo_test'];

/// Files that still have a leading "Returns". Shrink-only.
///
/// The multi-pass `--fix` work is rewriting these files, so they are left
/// alone to avoid merge conflicts.
// TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/146
// remove once the multi-pass --fix stack lands.
const Set<String> _shouldBeFixed = {
  'lib/src/fixable_rule.dart',
  'lib/src/rules/name_format_rule.dart',
  'lib/src/rules/trailing_whitespace_rule.dart',
  'lib/src/validation_session.dart',
  'lib/src/validator.dart',
};

const String _fix =
    'Start the doc comment with a noun phrase that names the result, or with a '
    'third-person verb that says what the member does ("Parses", "Finds"). See '
    '"No leading Returns" in documentation/knowledge/style_guide.md.';
