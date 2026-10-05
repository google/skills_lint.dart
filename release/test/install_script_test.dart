// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// scripts/install.sh is a bash script for macOS and Linux.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/checksums.dart';
import 'package:skills_lint_release/src/install_script.dart';
import 'package:skills_lint_release/src/macho.dart';
import 'package:skills_lint_release/src/paths.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:test/test.dart';

/// Fake `curl` that copies the release asset named by the URL from
/// `MOCK_RELEASE_DIR`, and appends the URL to `MOCK_CURL_LOG`.
const String _curl = r'''
#!/bin/bash
set -eu
outfile=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) outfile="$2"; shift ;;
    -*) ;;
    *) url="$1" ;;
  esac
  shift
done
echo "$url" >> "$MOCK_CURL_LOG"
cp "${MOCK_RELEASE_DIR}/$(basename "$url")" "$outfile"
''';

/// Fake `uname` that prints `MOCK_UNAME_S` for `-s` and `MOCK_UNAME_M` for
/// `-m`.
const String _uname = r'''
#!/bin/bash
if [ "$1" = "-s" ]; then echo "$MOCK_UNAME_S"; else echo "$MOCK_UNAME_M"; fi
''';

/// Fake `sw_vers` that prints `MOCK_SW_VERS`.
const String _swVers = r'''
#!/bin/bash
echo "$MOCK_SW_VERS"
''';

/// The `uname -s` and `uname -m` output of a machine that runs [target].
(String, String) _unameFor(String target) {
  final [String os, String arch] = target.split('-');
  return (os == 'macos' ? 'Darwin' : 'Linux', arch == 'x64' ? 'x86_64' : 'arm64');
}

void main() {
  late Directory temp;
  late Directory release;
  late Directory bin;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('install_script_test.');
    release = Directory(p.join(temp.path, 'release'))..createSync();
    bin = Directory(p.join(temp.path, 'bin'))..createSync();
    for (final (String name, String script) in [
      ('curl', _curl),
      ('uname', _uname),
      ('sw_vers', _swVers),
    ]) {
      File(p.join(bin.path, name)).writeAsStringSync(script);
      Process.runSync('chmod', ['+x', p.join(bin.path, name)]);
    }
    // The archives of every target, built as the release workflow builds
    // them, but holding a script instead of a compiled executable.
    for (final String target in supportedTargets) {
      final stage = Directory(p.join(temp.path, 'stage-$target'))..createSync();
      File(p.join(stage.path, binaryName(target))).writeAsStringSync('#!/bin/sh\necho $target\n');
      Process.runSync('chmod', ['+x', p.join(stage.path, binaryName(target))]);
      File(p.join(stage.path, 'LICENSE')).writeAsStringSync('license');
      writeChecksum(await writeArchive(stage: stage, target: target, outputDir: release));
    }
    mergeChecksums(release);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  /// Runs the install [script], `scripts/install.sh` by default, on a fake
  /// machine that runs [target] and has [macosVersion] if it is a Mac. Sets
  /// `VERSION` to [version]; install.sh treats an empty `VERSION` as unset.
  Future<ProcessResult> install(
    String target, {
    String macosVersion = macosMinimumVersion,
    String? script,
    String version = '0.0.0',
  }) {
    final (String unameS, String unameM) = _unameFor(target);
    return Process.run(
      'bash',
      [script ?? p.join(skillsLintPackageDir, 'scripts', 'install.sh')],
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'MOCK_RELEASE_DIR': release.path,
        'MOCK_CURL_LOG': p.join(temp.path, 'curl.log'),
        'MOCK_UNAME_S': unameS,
        'MOCK_UNAME_M': unameM,
        'MOCK_SW_VERS': macosVersion,
        'INSTALL_DIR': p.join(temp.path, 'install-$target'),
        'VERSION': version,
      },
    );
  }

  for (final String target in supportedTargets) {
    test('installs the $target archive and SHA256SUMS of a release', () async {
      final ProcessResult result = await install(target);
      expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      final ProcessResult installed = await Process.run(
        p.join(temp.path, 'install-$target', 'skills_lint'),
        [],
      );
      expect(installed.stdout, '$target\n');
    });
  }

  test('refuses a Mac older than the minimum macOS version of the executables', () async {
    final int major = int.parse(macosMinimumVersion.split('.').first);
    final ProcessResult result = await install('macos-arm64', macosVersion: '${major - 1}.9');
    expect(result.exitCode, 1, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(File(p.join(temp.path, 'install-macos-arm64', 'skills_lint')).existsSync(), isFalse);
  });

  group('installScriptForVersion', () {
    test('writes an install.sh that installs the given version by default', () async {
      final String original = File(
        p.join(skillsLintPackageDir, 'scripts', 'install.sh'),
      ).readAsStringSync();
      final String script = p.join(temp.path, 'install.sh');
      File(script).writeAsStringSync(installScriptForVersion(original, '1.2.3'));
      final ProcessResult result = await install('linux-x64', script: script, version: '');
      expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect(
        File(p.join(temp.path, 'curl.log')).readAsLinesSync(),
        everyElement(contains('/releases/download/${tagPrefix}1.2.3/')),
      );
    });

    test('throws when the script has no default version to replace', () {
      expect(
        () => installScriptForVersion('#!/bin/bash\n', '1.2.3'),
        throwsA(isA<ReleaseException>()),
      );
    });
  });
}
