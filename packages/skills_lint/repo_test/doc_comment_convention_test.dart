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
/// does. A later paragraph may still start with "Returns".
///
/// Only `lib/`, `release/lib/` and `repo_test/` are scanned, the scope that
/// issue #146 set. `bin/`, `benchmark/` and `test/` still have leading
/// "Returns"; add each directory here once it is fixed. `third_party/` is
/// vendored and keeps its upstream wording. Drop the rule if the style
/// guide's bullet changes.
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
        if (!_shouldBeFixed.containsKey(source.path)) ...findLeadingReturns(source),
    ];
    expectNoViolations(violations, fix: _fix);
  });

  test('each file in the allowlist has exactly its listed count', () {
    final List<String> mismatches = [
      for (final MapEntry(key: path, value: listed) in _shouldBeFixed.entries)
        if (_countIn(sources, path) case final int found when found != listed)
          '$path: listed $listed, found $found',
    ];
    expect(
      mismatches,
      isEmpty,
      reason:
          'Fix new violations in these files. When the count drops, lower it, '
          'and once it reaches 0, remove it from the allowlist.',
    );
  });
}

/// The number of leading "Returns" in the file at [path], or 0 if
/// [sources] has no such file.
int _countIn(List<Source> sources, String path) => [
  for (final Source source in sources)
    if (source.path == path) ...findLeadingReturns(source),
].length;

const List<String> _scannedDirectories = ['lib', '../../release/lib', 'repo_test'];

/// The number of leading "Returns" in each file that still has some.
/// Shrink-only.
///
/// The multi-pass `--fix` work is rewriting these files, so they are left
/// alone to avoid merge conflicts.
// TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/146
// remove once the multi-pass --fix stack lands.
const Map<String, int> _shouldBeFixed = {
  'lib/src/fixable_rule.dart': 1,
  'lib/src/rules/name_format_rule.dart': 3,
  'lib/src/rules/trailing_whitespace_rule.dart': 1,
  'lib/src/validation_session.dart': 1,
  'lib/src/validator.dart': 1,
};

const String _fix =
    'Start the doc comment with a noun phrase that names the result, or with a '
    'third-person verb that says what the member does ("Parses", "Finds"). See '
    '"No leading Returns" in documentation/knowledge/style_guide.md.';
