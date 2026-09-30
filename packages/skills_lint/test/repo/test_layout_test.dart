// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Pins the split between product tests and repo checks.
///
/// Product tests in `test/` check that skills_lint behaves correctly. Repo
/// checks in `test/repo/` check that this repository follows its own
/// conventions. CI runs them as separate steps (`dart test -x repo` and
/// `dart test -t repo`), and package:test selects tests by tag, not by folder.
/// So the folder and the tag must agree.
@Tags(['repo'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/repo_paths.dart';

void main() {
  final Directory testRoot = Directory(p.join(packageRoot, 'test'));
  final String repoTestRoot = p.join(testRoot.path, 'repo');
  final List<File> testFiles = [
    for (final File file in testRoot.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('_test.dart')) file,
  ]..sort((a, b) => a.path.compareTo(b.path));

  test('every test file under test/repo/ is tagged repo', () {
    final List<String> untagged = [
      for (final File file in testFiles)
        if (p.isWithin(repoTestRoot, file.path) && !_hasRepoTag(file)) _display(file),
    ];
    expect(
      untagged,
      isEmpty,
      reason:
          "Add `@Tags(['repo'])` above `library;` at the top of each file, "
          'so `dart test -x repo` leaves it out of the product run.',
    );
  });

  test('no test file outside test/repo/ is tagged repo', () {
    final List<String> misplaced = [
      for (final File file in testFiles)
        if (!p.isWithin(repoTestRoot, file.path) && _hasRepoTag(file)) _display(file),
    ];
    expect(
      misplaced,
      isEmpty,
      reason:
          'A repo check goes in test/repo/. A product test does not declare '
          "`@Tags(['repo'])`. Move the file or remove the tag.",
    );
  });
}

final RegExp _repoTag = RegExp(r"^@Tags\(\[\s*'repo'\s*\]\)", multiLine: true);

bool _hasRepoTag(File file) => _repoTag.hasMatch(file.readAsStringSync());

/// Returns [file] relative to the package root, with `/` separators on every
/// OS so the failure message reads the same everywhere.
String _display(File file) => p.split(p.relative(file.path, from: packageRoot)).join('/');
