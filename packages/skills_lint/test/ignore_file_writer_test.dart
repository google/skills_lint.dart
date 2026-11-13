// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests of [IgnoreFileTarget] and [IgnoreFileWriter], which load, initialize,
/// and save baseline/ignore files within each target's [WriteBoundary].
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/ignore_entry.dart';
import 'package:skills_lint/src/models/skills_ignores.dart';
import 'package:skills_lint/src/reporters/text_reporter.dart';
import 'package:skills_lint/src/write/ignore_file_writer.dart';
import 'package:skills_lint/src/write/write_boundary.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory repo;
  late Directory outside;
  late StringBuffer err;
  late IgnoreFileWriter writer;

  setUp(() async {
    root = Directory(
      (await Directory.systemTemp.createTemp(
        'ignore_file_writer_test.',
      )).resolveSymbolicLinksSync(),
    );
    addTearDown(() => root.delete(recursive: true));
    repo = Directory(p.join(root.path, 'repo'))..createSync();
    outside = Directory(p.join(root.path, 'outside'))..createSync();
    err = StringBuffer();
    writer = IgnoreFileWriter(TextReporter(out: StringBuffer(), err: err));
  });

  group('load', () {
    test('does not create a missing default ignore file', () async {
      final target = IgnoreFileTarget.defaultIn(repo, targetBoundary: WriteBoundary(repo.path));

      final SkillsIgnores ignores = await writer.load(target);

      expect(ignores.skills, isEmpty);
      expect(File(target.path).existsSync(), isFalse);
      expect(writer.writeRefused, isFalse);
    });

    test('creates a missing configured ignore file inside the configuration directory', () async {
      final String ignorePath = p.join(repo.path, 'custom_ignore.json');
      final target = IgnoreFileTarget.fromConfiguration(
        ignorePath,
        configDirectory: repo.path,
        allowWrite: const [],
      );

      final SkillsIgnores ignores = await writer.load(target);

      expect(ignores.skills, isEmpty);
      expect(File(ignorePath).existsSync(), isTrue);
      expect(writer.writeRefused, isFalse);
    });

    test('refuses creating a missing configured ignore file outside its boundary', () async {
      final String ignorePath = p.join(outside.path, 'custom_ignore.json');
      final target = IgnoreFileTarget.fromConfiguration(
        ignorePath,
        configDirectory: repo.path,
        allowWrite: const [],
      );

      await writer.load(target);

      expect(File(ignorePath).existsSync(), isFalse);
      expect(writer.writeRefused, isTrue);
      expect(err.toString(), contains("Error: did not write ignore file '$ignorePath'"));
    });

    test('creates a missing override ignore file outside the repository', () async {
      final String ignorePath = p.join(outside.path, 'override_ignore.json');
      final target = IgnoreFileTarget.fromOverride(ignorePath);

      await writer.load(target);

      expect(File(ignorePath).existsSync(), isTrue);
      expect(writer.writeRefused, isFalse);
    });

    test(
      'removes and refuses a created shared ignore file when a later target narrows the boundary',
      () async {
        final subdir = Directory(p.join(repo.path, 'sub'))..createSync();
        final String sharedPath = p.join(repo.path, 'shared_ignore.json');

        await writer.load(
          IgnoreFileTarget.fromConfiguration(
            sharedPath,
            configDirectory: repo.path,
            allowWrite: const [],
          ),
        );
        expect(File(sharedPath).existsSync(), isTrue);

        writer.recordBoundary(
          IgnoreFileTarget.fromConfiguration(
            sharedPath,
            configDirectory: subdir.path,
            allowWrite: const [],
          ),
        );

        expect(File(sharedPath).existsSync(), isFalse);
        expect(writer.writeRefused, isTrue);
        expect(err.toString(), contains("Error: did not write ignore file '$sharedPath'"));
      },
    );

    test(
      'preserves a pre-existing dangling symlink and deletes the created target when narrowed',
      () async {
        final subdir = Directory(p.join(repo.path, 'sub'))..createSync();
        final siblingDir = Directory(p.join(repo.path, 'other'))..createSync();
        final String targetFile = p.join(siblingDir.path, 'created.json');
        final String linkPath = p.join(subdir.path, 'ignore.json');
        Link(linkPath).createSync(targetFile);

        await writer.load(
          IgnoreFileTarget.fromConfiguration(
            linkPath,
            configDirectory: repo.path,
            allowWrite: const [],
          ),
        );
        expect(File(targetFile).existsSync(), isTrue);

        writer.recordBoundary(
          IgnoreFileTarget.fromConfiguration(
            linkPath,
            configDirectory: subdir.path,
            allowWrite: const [],
          ),
        );

        expect(File(targetFile).existsSync(), isFalse);
        expect(FileSystemEntity.typeSync(linkPath, followLinks: false), FileSystemEntityType.link);
        expect(writer.writeRefused, isTrue);
      },
    );
  });

  group('saveBaseline', () {
    test('enforces every boundary recorded for a shared ignore file path', () async {
      final subdir = Directory(p.join(repo.path, 'sub'))..createSync();
      final String sharedPath = p.join(repo.path, 'shared_ignore.json');
      File(sharedPath).writeAsStringSync('{"skills": {}}');

      // Target A permits `repo/`, while Target B only permits `repo/sub/`.
      await writer.load(
        IgnoreFileTarget.fromConfiguration(
          sharedPath,
          configDirectory: repo.path,
          allowWrite: const [],
        ),
      );
      writer.recordBoundary(
        IgnoreFileTarget.fromConfiguration(
          sharedPath,
          configDirectory: subdir.path,
          allowWrite: const [],
        ),
      );

      await writer.saveBaseline(
        sharedPath,
        SkillsIgnores(
          skills: {
            'foo': [IgnoreEntry(ruleId: 'invalid-skill-name', fileName: 'SKILL.md')],
          },
        ),
      );

      expect(writer.writeRefused, isTrue);
      expect(jsonDecode(File(sharedPath).readAsStringSync()), {'skills': <String, dynamic>{}});
    });

    test('carries load problems across a skill rename and reports dropped entries once', () async {
      final oldSkill = Directory(p.join(repo.path, 'old-skill'))..createSync();
      final newSkill = Directory(p.join(repo.path, 'new-skill'))..createSync();
      final boundary = WriteBoundary(repo.path);
      final oldTarget = IgnoreFileTarget.defaultIn(oldSkill, targetBoundary: boundary);
      File(oldTarget.path).writeAsStringSync('{"skills": {"old-skill": [{"rule_id": "x"}]}}');

      await writer.load(oldTarget);
      final IgnoreFileTarget newTarget = oldTarget.afterSkillRename(newSkill);
      File(oldTarget.path).renameSync(newTarget.path);
      writer.moveRenamedIgnoreFile(oldIgnorePath: oldTarget.path, newTarget: newTarget);

      await writer.saveBaseline(newTarget.path, SkillsIgnores(skills: {}));
      await writer.saveBaseline(newTarget.path, SkillsIgnores(skills: {}));

      expect(
        'Replacing ${newTarget.path} without carrying over 1 malformed entry'.allMatches(
          err.toString(),
        ),
        hasLength(1),
      );
    });
  });
}
