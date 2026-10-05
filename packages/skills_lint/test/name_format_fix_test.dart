// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/rules/name_format_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

const _content = '---\nname: Old_Name\ndescription: d\n---\nbody\n';

void main() {
  group('NameFormatRule.fix', () {
    test('rewrites name to a directory name that is a valid skill name', () async {
      final String fixed = await NameFormatRule().fix(
        'SKILL.md',
        _content,
        Directory(p.join('skills', 'my-skill')),
      );
      expect(fixed, '---\nname: my-skill\ndescription: d\n---\nbody\n');
    });

    for (final dirName in ['My Skill #1', 'a: b', '123', 'null', 'true', '~', '[a]', '-']) {
      test('leaves the file unchanged for directory "$dirName"', () async {
        final String fixed = await NameFormatRule().fix(
          'SKILL.md',
          _content,
          Directory(p.join('skills', dirName)),
        );
        expect(fixed, _content);
      });
    }
  });

  group('--fix with a directory name that is not a valid skill name', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('name_fix_test.');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('reports the name error and leaves the file and directory unchanged', () async {
      final Directory skillsDir = await Directory(p.join(tempDir.path, 'skills')).create();
      final Directory skillDir = await Directory(p.join(skillsDir.path, 'My Skill #1')).create();
      final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
      await skillFile.writeAsString(_content);

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '--fix',
        '-d',
        skillsDir.path,
      ]);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      await process.shouldExit(1);

      expect(stdout, isNot(contains('Renamed')));
      expect(stderr, contains('does not match the parent directory name'));
      expect(skillDir.existsSync(), isTrue);
      expect(await skillFile.readAsString(), _content);
      expect(skillsDir.listSync().map((e) => p.basename(e.path)), ['My Skill #1']);
    });
  });
}
