// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Covers how PubArchiveLoader finds the package, runs pub and reads the
// archive, and that each failure comes back as a message instead of an
// exception. A fake stands in for pub here. The CLI test in
// pub_archive_includes_skill_cli_test.dart runs the real one.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/pub_archive.dart';
import 'package:skills_lint/src/pub_archive_loader.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pub_archive_loader_test.');
  });

  tearDown(() => tempDir.delete(recursive: true));

  /// Creates a package in [name] under the temp directory, with
  /// [pubspecExtra] appended to its pubspec, and returns its root.
  Future<Directory> createPackage(String name, {String pubspecExtra = ''}) async {
    final Directory root = await Directory(p.join(tempDir.path, name)).create();
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString('name: $name\n$pubspecExtra');
    return root;
  }

  Directory skillIn(Directory packageRoot, String skillName) =>
      Directory(p.join(packageRoot.path, 'skills', skillName));

  test('lists the archive files that pub writes in the package root', () async {
    final Directory root = await createPackage('my_pkg');
    final pub = FakePub(archiveFiles: ['pubspec.yaml', 'skills/my-pkg-a/SKILL.md']);

    final PubArchive archive = await PubArchiveLoader(
      runProcess: pub.run,
    ).archiveFor(skillIn(root, 'my-pkg-a'));

    expect(archive, isA<PubArchiveFiles>());
    final files = archive as PubArchiveFiles;
    expect(files.packageRoot, p.normalize(root.absolute.path));
    expect(files.files, {'pubspec.yaml', 'skills/my-pkg-a/SKILL.md'});
    expect(pub.workingDirectories, [files.packageRoot]);
  });

  test('runs pub once per package', () async {
    final Directory first = await createPackage('first');
    final Directory second = await createPackage('second');
    final pub = FakePub();
    final loader = PubArchiveLoader(runProcess: pub.run);

    await loader.archiveFor(skillIn(first, 'first-a'));
    await loader.archiveFor(skillIn(first, 'first-b'));
    await loader.archiveFor(skillIn(second, 'second-a'));

    expect(pub.workingDirectories.map(p.basename), ['first', 'second']);
  });

  test('runs pub again after clear', () async {
    final Directory root = await createPackage('my_pkg');
    final pub = FakePub();
    final loader = PubArchiveLoader(runProcess: pub.run);

    await loader.archiveFor(skillIn(root, 'my-pkg-a'));
    loader.clear();
    await loader.archiveFor(skillIn(root, 'my-pkg-a'));

    expect(pub.workingDirectories, hasLength(2));
  });

  group('reports, without running pub,', () {
    test('a skill with no pubspec.yaml above it', () async {
      final pub = FakePub();

      final PubArchive archive = await PubArchiveLoader(
        runProcess: pub.run,
      ).archiveFor(Directory(p.join(tempDir.path, 'skills', 'a')));

      expect((archive as PubArchiveUnavailable).reason, contains('No pubspec.yaml found'));
      expect(pub.workingDirectories, isEmpty);
    });

    test('a package that sets publish_to: none', () async {
      final Directory root = await createPackage('my_pkg', pubspecExtra: 'publish_to: none\n');
      final pub = FakePub();

      final PubArchive archive = await PubArchiveLoader(
        runProcess: pub.run,
      ).archiveFor(skillIn(root, 'my-pkg-a'));

      expect((archive as PubArchiveUnavailable).reason, contains('sets publish_to: none'));
      expect(pub.workingDirectories, isEmpty);
    });
  });

  group('reports', () {
    test('that dart is not on PATH', () async {
      final Directory root = await createPackage('my_pkg');
      Future<ProcessResult> missingDart(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) => throw ProcessException(executable, arguments, 'No such file or directory', 2);

      final PubArchive archive = await PubArchiveLoader(
        runProcess: missingDart,
      ).archiveFor(skillIn(root, 'my-pkg-a'));

      expect(
        (archive as PubArchiveUnavailable).reason,
        allOf(contains('No such file or directory'), contains('needs the Dart SDK on PATH')),
      );
      expect(archive.packageRoot, p.normalize(root.absolute.path));
    });

    test('a pub that fails, such as one without --to-archive', () async {
      final Directory root = await createPackage('my_pkg');
      final pub = FakePub(exitCode: 64, stderr: 'Could not find an option named "--to-archive".');

      final PubArchive archive = await PubArchiveLoader(
        runProcess: pub.run,
      ).archiveFor(skillIn(root, 'my-pkg-a'));

      expect(
        (archive as PubArchiveUnavailable).reason,
        allOf(
          contains('failed in ${p.normalize(root.absolute.path)} with exit code 64'),
          contains('Could not find an option named "--to-archive".'),
        ),
      );
    });

    test('a pub that exits 0 without writing the archive', () async {
      final Directory root = await createPackage('my_pkg');
      Future<ProcessResult> silentPub(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async => ProcessResult(0, 0, '', '');

      final PubArchive archive = await PubArchiveLoader(
        runProcess: silentPub,
      ).archiveFor(skillIn(root, 'my-pkg-a'));

      expect((archive as PubArchiveUnavailable).reason, contains('Could not read the archive'));
    });
  });
}
