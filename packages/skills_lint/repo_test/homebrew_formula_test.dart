// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/homebrew_formula.dart';
import 'src/repo_paths.dart';
import 'src/source_conventions.dart';

/// Checks `Formula/skills_lint.rb` against the release targets, the package
/// version, the minimum macOS version and the Homebrew workflow.
///
/// `src/homebrew_formula.dart` says why. `checkers/homebrew_formula_test.dart`
/// pins what each check reports on small formulas. `Formula/README.md` says
/// how to update the formula.
void main() {
  const formulaPath = 'Formula/skills_lint.rb';
  final String content = _read(formulaPath);
  final HomebrewFormula formula = parseFormula(content);
  final List<ReleaseTarget> targets = _releaseTargets();
  final List<String> installable = formulaTargets(targets.map((target) => target.name));

  test('has one block with the release url and a sha256 for each release target', () {
    expectNoViolations(
      findArchiveViolations(formulaPath, formula, installable),
      fix:
          'Give each target in $_targetsSource that Homebrew can install one on_<os> and '
          "on_<arch> block, with the url of its archive and the sha256 from that release's "
          'SHA256SUMS. Replace every placeholder in the same change.',
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

  test('depends_on macos: is inside on_macos', () {
    expectNoViolations(
      findMacosViolations(formulaPath, formula, null),
      fix: 'Put depends_on macos: inside the on_macos block of $formulaPath.',
    );
  });

  final macho = File(p.join(repoRoot, 'release', 'lib', 'src', 'macho.dart'));
  test('depends_on macos: matches macosMinimumVersion', () {
    final RegExpMatch? match = RegExp(
      r"const String macosMinimumVersion = '([\d.]+)';",
    ).firstMatch(macho.readAsStringSync());
    expect(match, isNotNull, reason: 'Found no macosMinimumVersion constant in ${macho.path}.');
    expectNoViolations(
      findMacosViolations(formulaPath, formula, match!.group(1)),
      fix:
          'Set depends_on macos: inside on_macos in $formulaPath to the symbol for '
          'macosMinimumVersion in release/lib/src/macho.dart.',
    );
  }, skip: macho.existsSync() ? null : 'release/lib/src/macho.dart does not exist on this branch.');

  test('the Homebrew workflow installs on each target with the runner that builds it', () {
    final workflow = loadYaml(_read('.github/workflows/homebrew.yaml')) as YamlMap;
    final Object? include = switch (workflow) {
      {'jobs': {'install': {'strategy': {'matrix': {'include': final Object? value}}}}} => value,
      _ => null,
    };
    expect(
      [
        for (final entry in include is YamlList ? include : const [])
          if (entry is YamlMap) '${entry['target']} on ${entry['os']}',
      ],
      unorderedEquals([
        for (final target in targets)
          if (installable.contains(target.name)) '${target.name} on ${target.runner}',
      ]),
      reason:
          'jobs.install.strategy.matrix.include in .github/workflows/homebrew.yaml must list '
          'each target that the formula installs, with the runner from $_targetsSource.',
    );
  });

  test('the package README has no Homebrew install section while placeholders remain', () {
    // `brew install` fails until the first release with executables, so
    // users must not find the commands before then. Formula/README.md holds
    // the section that the first real release adds.
    final String readme = _read('packages/skills_lint/README.md');
    expect(
      formula.hasPlaceholders && readme.contains('google/skills-lint'),
      isFalse,
      reason:
          'Move the Homebrew install commands out of packages/skills_lint/README.md until '
          '$formulaPath has no placeholders.',
    );
  });
}

/// A release target and the GitHub-hosted runner that builds it.
typedef ReleaseTarget = ({String name, String runner});

/// The file that lists the release targets, relative to the repository root.
const String _targetsSource = 'release/lib/src/archive.dart';

/// The release targets, as `releaseTargets` in [_targetsSource] lists them.
///
/// [_fallbackTargets] applies only where [_targetsSource] does not exist.
List<ReleaseTarget> _releaseTargets() {
  final file = File(p.join(repoRoot, _targetsSource));
  if (!file.existsSync()) {
    return _fallbackTargets;
  }
  final List<ReleaseTarget> targets = [
    for (final RegExpMatch match in RegExp(
      r"\(name: '([^']+)', abi: [\w.]+, runner: '([^']+)'\)",
    ).allMatches(file.readAsStringSync()))
      (name: match.group(1)!, runner: match.group(2)!),
  ];
  if (targets.isEmpty) {
    throw StateError(
      'Found no (name: ..., abi: ..., runner: ...) records in $_targetsSource. Update '
      '_releaseTargets in repo_test/homebrew_formula_test.dart to read releaseTargets.',
    );
  }
  return targets;
}

/// The release targets of the release workflow, for branches that do not
/// have [_targetsSource].
const List<ReleaseTarget> _fallbackTargets = [
  (name: 'macos-arm64', runner: 'macos-latest'),
  (name: 'macos-x64', runner: 'macos-26-intel'),
  (name: 'linux-x64', runner: 'ubuntu-latest'),
  (name: 'linux-arm64', runner: 'ubuntu-24.04-arm'),
];

String _read(String path) => File(p.joinAll([repoRoot, ...p.posix.split(path)])).readAsStringSync();
