// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/homebrew/archive_violations.dart';
import 'src/homebrew/homebrew_formula.dart';
import 'src/homebrew/macos_violations.dart';
import 'src/homebrew/version_violations.dart';
import 'src/repo_paths.dart';
import 'src/source_conventions.dart';

/// The `macosMinimumVersion` declaration in `release/lib/src/macho.dart`,
/// such as `const String macosMinimumVersion = '14.0';`. Group 1 is the
/// version.
final RegExp _macosMinimumVersionDeclaration = RegExp(
  r"const String macosMinimumVersion = '([\d.]+)';",
);

/// Checks `Formula/skills_lint.rb` against the release targets, the package
/// version, the minimum macOS version and the package README.
///
/// `brew audit` accepts a formula whose `on_arm` block names the x64 archive,
/// whose archives share a `sha256`, or whose `version` is not a release. Each
/// of these breaks `brew install` on some platform.
/// `checkers/homebrew_formula_test.dart` tests each check on small formulas.
void main() {
  const formulaPath = 'Formula/skills_lint.rb';
  const machoPath = 'release/lib/src/macho.dart';
  final String content = _read(formulaPath);
  final formula = HomebrewFormula.parse(content);

  late List<String> targets;
  setUpAll(() async {
    targets = await _homebrewTargets();
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
    final RegExpMatch? match = _macosMinimumVersionDeclaration.firstMatch(_read(machoPath));
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
    final List<String> readmeLines = [
      for (final String line in _read('packages/skills_lint/README.md').split('\n'))
        line.trimRight(),
    ];
    expect(readmeLines, contains('brew tap $tap https://github.com/google/skills_lint.dart'));
    expect(readmeLines, contains('brew install $tap/$name'));
  });
}

/// Returns the name of each target that the formula needs a block for, such
/// as `macos-arm64`.
///
/// They come from `releaseTargets` in `release/lib/src/archive.dart`, the one
/// list of targets. The `release` package is not a dependency of
/// `skills_lint`, so this runs its `homebrew-matrix` command, which also gives
/// `homebrew.yaml` its install matrix.
Future<List<String>> _homebrewTargets() async {
  const prefix = 'matrix=';
  final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
    'run',
    'bin/release.dart',
    'homebrew-matrix',
  ], workingDirectory: p.join(repoRoot, 'release'));
  final output = result.stdout as String;
  expect(result.exitCode, 0, reason: 'stdout: $output\nstderr: ${result.stderr}');
  expect(output, startsWith(prefix));
  final matrix = jsonDecode(output.substring(prefix.length)) as Map<String, Object?>;
  return [
    for (final entry in matrix['include']! as List<Object?>)
      (entry! as Map<String, Object?>)['target']! as String,
  ];
}

String _read(String path) => File(p.joinAll([repoRoot, ...p.posix.split(path)])).readAsStringSync();
