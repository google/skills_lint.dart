// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// The archives are built and run on the macOS and Linux release runners
// only, and these tests run a shell script as the executable.
@TestOn('!windows')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:test/test.dart';

const String _target = 'linux-x64';

void main() {
  late Directory temp;
  late Directory stage;
  late Directory dist;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('archive_test.');
    stage = Directory(p.join(temp.path, 'stage'))..createSync();
    dist = Directory(p.join(temp.path, 'dist'))..createSync();
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  /// Writes a fake executable that exits with [exitCode], and a LICENSE.
  void stageFiles({int exitCode = 0}) {
    final executable = File(p.join(stage.path, binaryName(_target)))
      ..writeAsStringSync('#!/bin/sh\nexit $exitCode\n');
    Process.runSync('chmod', ['+x', executable.path]);
    File(p.join(stage.path, 'LICENSE')).writeAsStringSync('license');
  }

  Future<List<String>> listArchive(File archive) async {
    final ProcessResult result = await Process.run('tar', ['-tzf', archive.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).trim().split('\n')..sort();
  }

  test('archiveName is the name scripts/install.sh downloads', () {
    expect(archiveName('macos-arm64'), 'skills_lint-macos-arm64.tar.gz');
    expect(binaryName('macos-arm64'), 'skills_lint-macos-arm64');
  });

  test('hostTarget names the supported targets', () {
    expect(hostTarget(Abi.macosArm64), 'macos-arm64');
    expect(hostTarget(Abi.macosX64), 'macos-x64');
    expect(hostTarget(Abi.linuxX64), 'linux-x64');
    expect(hostTarget(Abi.linuxArm64), isNull);
    expect(hostTarget(Abi.windowsX64), isNull);
    expect(supportedTargets, ['macos-arm64', 'macos-x64', 'linux-x64']);
  });

  group('writeArchive', () {
    test('holds the executable and LICENSE at the top level', () async {
      stageFiles();
      final File archive = await writeArchive(stage: stage, target: _target, outputDir: dist);
      expect(p.basename(archive.path), 'skills_lint-linux-x64.tar.gz');
      expect(await listArchive(archive), ['LICENSE', 'skills_lint-linux-x64']);
    });

    test('throws when LICENSE is missing', () async {
      stageFiles();
      File(p.join(stage.path, 'LICENSE')).deleteSync();
      await expectLater(
        writeArchive(stage: stage, target: _target, outputDir: dist),
        throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains('LICENSE'))),
      );
    });
  });

  group('verifyArchive', () {
    test('passes when the archive holds a working executable and LICENSE', () async {
      stageFiles();
      final File archive = await writeArchive(stage: stage, target: _target, outputDir: dist);
      await verifyArchive(archive, _target);
    });

    test('throws when the archive holds another file', () async {
      stageFiles();
      File(p.join(stage.path, 'extra')).writeAsStringSync('extra');
      final archive = File(p.join(dist.path, archiveName(_target)));
      Process.runSync('tar', [
        '-czf',
        archive.path,
        '-C',
        stage.path,
        binaryName(_target),
        'LICENSE',
        'extra',
      ]);
      await expectLater(
        verifyArchive(archive, _target),
        throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains('extra'))),
      );
    });

    test('throws when the executable fails', () async {
      stageFiles(exitCode: 3);
      final File archive = await writeArchive(stage: stage, target: _target, outputDir: dist);
      await expectLater(
        verifyArchive(archive, _target),
        throwsA(
          isA<ReleaseException>().having((e) => e.message, 'message', contains('exit code 3')),
        ),
      );
    });
  });
}
