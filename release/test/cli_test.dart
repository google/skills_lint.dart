// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/checksums.dart';
import 'package:skills_lint_release/src/homebrew_formula.dart';
import 'package:skills_lint_release/src/line_endings.dart';
import 'package:skills_lint_release/src/paths.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:skills_lint_release/src/release_notes.dart';
import 'package:test/test.dart';

/// Runs `bin/release.dart` with [arguments].
Future<ProcessResult> _release(List<String> arguments) => Process.run(Platform.resolvedExecutable, [
  'run',
  p.join(releasePackageDir, 'bin', 'release.dart'),
  ...arguments,
]);

void main() {
  test('licenses writes the notices to --output', () async {
    final Directory temp = Directory.systemTemp.createTempSync('cli_test.');
    addTearDown(() => temp.deleteSync(recursive: true));
    final String output = p.join(temp.path, 'LICENSE');
    final ProcessResult result = await _release(['licenses', '--output', output]);
    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(File(output).readAsStringSync(), allOf(contains('skills_lint'), contains('Dart SDK')));
  });

  test(
    "prepare without --release-version prints a dry run and writes the version's CHANGELOG.md section",
    () async {
      final Directory temp = Directory.systemTemp.createTempSync('cli_test.');
      addTearDown(() => temp.deleteSync(recursive: true));
      final String notes = p.join(temp.path, 'notes.md');
      final ProcessResult result = await _release([
        'prepare',
        '--event',
        'workflow_dispatch',
        '--ref-type',
        'branch',
        '--ref-name',
        'main',
        '--notes-output',
        notes,
      ]);
      expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect(result.stdout, contains('mode=${ReleaseMode.dryRun.name}\n'));
      expect(result.stdout, contains('matrix=${buildMatrix()}\n'));
      final String version = readPubspecVersion(
        File(p.join(skillsLintPackageDir, 'pubspec.yaml')).readAsStringSync(),
      );
      final String changelog = File(
        p.join(skillsLintPackageDir, 'CHANGELOG.md'),
      ).readAsStringSync();
      expect(changelog.normalizeLineTerminators(), contains(File(notes).readAsStringSync().trim()));
      expect(changelogSection(changelog, version), File(notes).readAsStringSync().trim());
    },
  );

  // The build workflow passes its version input to --release-version, and
  // that input is empty in a dry run.
  test('prepare reads an empty --release-version as a dry run', () async {
    final Directory temp = Directory.systemTemp.createTempSync('cli_test.');
    addTearDown(() => temp.deleteSync(recursive: true));
    final ProcessResult result = await _release([
      'prepare',
      '--event',
      'workflow_dispatch',
      '--ref-type',
      'branch',
      '--ref-name',
      'main',
      '--release-version',
      '', // An empty release version means a dry run.
      '--notes-output',
      p.join(temp.path, 'notes.md'),
    ]);
    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stdout, contains('mode=${ReleaseMode.dryRun.name}\n'));
  });

  test('homebrew-matrix prints a matrix entry for each target that Homebrew installs', () async {
    final ProcessResult result = await _release(['homebrew-matrix']);
    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    final stdout = result.stdout as String;
    expect(stdout, startsWith('matrix='));
    final matrix = jsonDecode(stdout.substring('matrix='.length)) as Map<String, Object?>;
    expect(
      [for (final entry in matrix['include']! as List<Object?>) (entry! as Map)['target']],
      [for (final ReleaseTarget target in homebrewTargets()) target.name],
    );
  });

  test('homebrew-formula --output writes the release formula there', () async {
    final Directory temp = Directory.systemTemp.createTempSync('cli_test.');
    addTearDown(() => temp.deleteSync(recursive: true));
    // Restores the committed formula if --output stops working and the
    // command writes there instead.
    final String committed = File(homebrewFormulaPath).readAsStringSync();
    addTearDown(() => File(homebrewFormulaPath).writeAsStringSync(committed));
    // A different checksum for each archive, so a checksum written for the
    // wrong archive fails the test.
    final Map<String, String> checksums = {
      for (final ReleaseTarget target in homebrewTargets())
        archiveName(target.name): '${sha256.convert(utf8.encode(target.name))}',
    };
    final sums = File(p.join(temp.path, sha256SumsName))
      ..writeAsStringSync(
        [for (final MapEntry(:key, :value) in checksums.entries) '$value  $key'].join('\n'),
      );
    final String output = p.join(temp.path, 'skills_lint.rb');
    final ProcessResult result = await _release([
      'homebrew-formula',
      '--version',
      '1.2.3',
      '--sha256sums',
      sums.path,
      '--output',
      output,
    ]);
    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    final FormulaValues written = readFormula(File(output).readAsStringSync());
    expect(written.version, '1.2.3');
    expect(written.checksums, checksums);
    expect(File(homebrewFormulaPath).readAsStringSync(), committed);
  });

  test('homebrew-formula needs --version and --sha256sums together', () async {
    for (final List<String> arguments in [
      ['--version', '1.2.3'],
      ['--sha256sums', sha256SumsName],
    ]) {
      final ProcessResult result = await _release(['homebrew-formula', ...arguments]);
      expect(result.exitCode, 64, reason: '$arguments\nstderr: ${result.stderr}');
      expect(result.stderr, contains('Give both --version and --sha256sums'));
    }
  });

  test('homebrew-formula --check rejects each option that writes a formula', () async {
    for (final List<String> option in [
      ['--version', '1.2.3'],
      ['--sha256sums', sha256SumsName],
      ['--output', 'skills_lint.rb'],
    ]) {
      final ProcessResult result = await _release(['homebrew-formula', '--check', ...option]);
      expect(result.exitCode, 64, reason: '$option\nstderr: ${result.stderr}');
      expect(result.stderr, contains('--check takes no other options'), reason: '$option');
    }
  });

  test('a release error exits with code 1 and names the problem', () async {
    final ProcessResult result = await _release([
      'prepare',
      '--event',
      'workflow_dispatch',
      '--ref-type',
      'branch',
      '--ref-name',
      'not-the-release-branch',
      '--release-version',
      '0.0.0',
      '--notes-output',
      p.join(Directory.systemTemp.path, 'unused-notes.md'),
    ]);
    expect(result.exitCode, 1, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stderr, contains('release: error: '));
    expect(result.stderr, contains('not-the-release-branch'));
  });

  test('verify-draft fails on a run that is not on a release tag', () async {
    final Directory temp = Directory.systemTemp.createTempSync('cli_test.');
    addTearDown(() => temp.deleteSync(recursive: true));
    final release = File(p.join(temp.path, 'release.json'))
      ..writeAsStringSync('{"isDraft": true, "isPrerelease": false}');
    final ProcessResult result = await _release([
      'verify-draft',
      '--ref-type',
      'branch',
      '--tag',
      'main',
      '--repository',
      'google/skills_lint.dart',
      '--commit',
      '0123456789abcdef0123456789abcdef01234567',
      '--release-json',
      release.path,
      '--assets',
      temp.path,
      '--summary',
      p.join(temp.path, 'summary.md'),
    ]);
    expect(result.exitCode, 1, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stderr, contains('Run this workflow on a $tagPrefix<version> tag, not main'));
    expect(File(p.join(temp.path, 'summary.md')).existsSync(), isFalse);
  });

  test('a usage error exits with code 64', () async {
    final ProcessResult result = await _release(['prepare']);
    expect(result.exitCode, 64, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
  });

  test('checksums merges the .sha256 files in the directory into SHA256SUMS', () async {
    final Directory temp = Directory.systemTemp.createTempSync('cli_test.');
    addTearDown(() => temp.deleteSync(recursive: true));
    writeChecksum(File(p.join(temp.path, 'skills_lint-linux-x64.tar.gz'))..writeAsStringSync('a'));
    final ProcessResult result = await _release(['checksums', temp.path]);
    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stdout, endsWith('  skills_lint-linux-x64.tar.gz\n'));
    expect(File(p.join(temp.path, sha256SumsName)).readAsStringSync(), result.stdout);
  });

  test('package fails for a target that this machine does not build', () async {
    final String? host = hostTarget(Abi.current());
    final String other = supportedTargets.firstWhere((target) => target != host);
    final ProcessResult result = await _release([
      'package',
      '--target',
      other,
      '--output-dir',
      p.join(Directory.systemTemp.path, 'unused-dist'),
    ]);
    expect(result.exitCode, 1, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stderr, contains('not $other'));
  });
}
