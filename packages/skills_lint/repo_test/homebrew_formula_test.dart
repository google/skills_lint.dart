// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/homebrew_formula.dart';
import 'src/homebrew_targets.dart';
import 'src/repo_paths.dart';
import 'src/source_conventions.dart';

/// Checks `Formula/skills_lint.rb` against the release targets, the package
/// version, the minimum macOS version and the package README.
///
/// `src/homebrew_formula.dart` says why. `checkers/homebrew_formula_test.dart`
/// pins what each check reports on small formulas. RELEASING.md says how to
/// update the formula.
void main() {
  const formulaPath = 'Formula/skills_lint.rb';
  const machoPath = 'release/lib/src/macho.dart';
  final String content = _read(formulaPath);
  final HomebrewFormula formula = parseFormula(content);

  late List<String> targets;
  setUpAll(() async {
    targets = await readHomebrewTargets();
  });

  test('has one block with the release url and a sha256 for each target', () {
    expectNoViolations(
      findArchiveViolations(formulaPath, formula, targets),
      fix:
          'Give each target that `dart run bin/release.dart homebrew-matrix` in release/ prints '
          'one on_<os> and on_<arch> block, with the url of its archive and the sha256 from that '
          "release's SHA256SUMS. Replace every placeholder in the same change.",
    );
  });

  test('marks itself as a placeholder only while it has placeholder values', () {
    // The Homebrew workflow skips installing while the file says PLACEHOLDER
    // anywhere, including the header comment.
    expect(
      content.contains('PLACEHOLDER'),
      formula.hasPlaceholders,
      reason:
          'Remove every PLACEHOLDER comment from $formulaPath in the change that replaces '
          'the last placeholder value.',
    );
  });

  test('version is the pending release while placeholders remain, and a release after', () {
    final pubspec = loadYaml(_read('packages/skills_lint/pubspec.yaml')) as YamlMap;
    expectNoViolations(
      findVersionViolations(
        formulaPath,
        formula,
        pubspecVersion: pubspec['version'] as String,
        changelog: _read('packages/skills_lint/CHANGELOG.md'),
      ),
      fix:
          'Set version in $formulaPath to a skills_lint release that has executables. While '
          'the formula has placeholders, use the pubspec version without its -wip suffix.',
    );
  });

  test('depends_on macos: is inside on_macos and matches macosMinimumVersion', () {
    final RegExpMatch? match = RegExp(
      r"const String macosMinimumVersion = '([\d.]+)';",
    ).firstMatch(_read(machoPath));
    expect(match, isNotNull, reason: 'Found no macosMinimumVersion constant in $machoPath.');
    expectNoViolations(
      findMacosViolations(formulaPath, formula, match!.group(1)),
      fix:
          'Put depends_on macos: inside the on_macos block of $formulaPath, with the symbol '
          'for macosMinimumVersion in $machoPath.',
    );
  });

  test('the package README installs the formula by its tap and name', () {
    // Published README pages never change, so the commands there must keep
    // working: renaming the tap or the formula breaks them.
    final workflow = loadYaml(_read('.github/workflows/homebrew.yaml')) as YamlMap;
    final tap = (workflow['env'] as YamlMap)['TAP'] as String;
    final String name = p.basenameWithoutExtension(formulaPath);
    final String readme = _read('packages/skills_lint/README.md');
    expect(readme, contains('brew tap $tap https://github.com/google/skills_lint.dart\n'));
    expect(readme, contains('brew install $tap/$name\n'));
  });
}

String _read(String path) => File(p.joinAll([repoRoot, ...p.posix.split(path)])).readAsStringSync();
