// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/repo_paths.dart';

/// The targets that each GitHub Release has a `skills_lint-<target>.tar.gz`
/// archive for, as `.github/workflows/release.yaml` builds them.
const List<String> _targets = ['macos-arm64', 'macos-x64', 'linux-x64'];

final String _placeholderSha = 'sha256 "${'0' * 64}"';

void main() {
  final String formula = File(p.join(repoRoot, 'Formula', 'skills-lint.rb')).readAsStringSync();

  group('Homebrew formula', () {
    test('has one release archive url per target', () {
      final List<String> archives = [
        for (final RegExpMatch match in RegExp(
          r'url "https://github\.com/google/skills_lint\.dart/releases/download/'
          r'skills_lint-v#\{version\}/(skills_lint-[a-z0-9-]+\.tar\.gz)"',
        ).allMatches(formula))
          match.group(1)!,
      ];
      expect(archives, unorderedEquals([for (final t in _targets) 'skills_lint-$t.tar.gz']));
    });

    test('has a sha256 for each url', () {
      expect(RegExp(r'sha256 "[0-9a-f]{64}"').allMatches(formula), hasLength(_targets.length));
    });

    test('marks every placeholder sha256 as a PLACEHOLDER', () {
      final List<String> placeholderLines = [
        for (final String line in formula.split('\n'))
          if (line.contains(_placeholderSha)) line,
      ];
      expect(placeholderLines, everyElement(contains('# PLACEHOLDER')));
    });

    test('has either all real values or all placeholders', () {
      // The Homebrew workflow installs the formula only when it has no
      // PLACEHOLDER marker, so a partly updated formula must not pass.
      final int placeholders = _placeholderSha.allMatches(formula).length;
      expect(placeholders, anyOf(0, _targets.length));
      expect(formula.contains('PLACEHOLDER'), placeholders > 0);
    });
  });
}
