// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/checksums.dart';
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

  test("prepare prints a dry run and writes the version's CHANGELOG.md section", () async {
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
      '--release',
      'false',
      '--notes-output',
      notes,
    ]);
    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stdout, contains('mode=${ReleaseMode.dryRun.name}\n'));
    expect(result.stdout, contains('matrix=${buildMatrix()}\n'));
    final String version = readPubspecVersion(
      File(p.join(skillsLintPackageDir, 'pubspec.yaml')).readAsStringSync(),
    );
    final String changelog = File(p.join(skillsLintPackageDir, 'CHANGELOG.md')).readAsStringSync();
    expect(changelog, contains(File(notes).readAsStringSync().trim()));
    expect(changelogSection(changelog, version), File(notes).readAsStringSync().trim());
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

  test('a release error exits with code 1 and names the problem', () async {
    final ProcessResult result = await _release([
      'prepare',
      '--event',
      'workflow_dispatch',
      '--ref-type',
      'tag',
      '--ref-name',
      'skills_lint-v0.0.0-not-the-version',
      '--release',
      'true',
      '--notes-output',
      p.join(Directory.systemTemp.path, 'unused-notes.md'),
    ]);
    expect(result.exitCode, 1, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(result.stderr, contains('release: error: '));
    expect(result.stderr, contains('skills_lint-v0.0.0-not-the-version'));
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
