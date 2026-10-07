// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/rules/name_format_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

/// A `SKILL.md` whose frontmatter sets `name` to [name].
String _skillMd({String name = 'Old_Name'}) => '${buildFrontmatter(name: name)}body\n';

Future<String> _fix(String dirName) =>
    NameFormatRule().fix('SKILL.md', _skillMd(), Directory(p.join('skills', dirName)));

void main() {
  group('NameFormatRule.fix', () {
    for (final dirName in ['my-skill', 'my_skill', 'My_Skill', 'MySkill']) {
      test('rewrites name to directory name "$dirName"', () async {
        expect(await _fix(dirName), _skillMd(name: dirName));
      });
    }

    for (final dirName in [
      'My Skill #1',
      'a: b',
      '123',
      '1e3',
      '0x1f',
      'null',
      'Null',
      'true',
      'TRUE',
      '~',
      '[a]',
      '-',
      '---',
    ]) {
      test('leaves the file unchanged for directory "$dirName"', () async {
        expect(await _fix(dirName), _skillMd());
      });
    }
  });

  defineCliTests();
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  group('CLI --fix of invalid-skill-name', () {
    late Directory skillsDir;

    setUp(() async {
      final Directory tempDir = await Directory.systemTemp.createTemp('name_fix_test.');
      addTearDown(() => tempDir.delete(recursive: true));
      skillsDir = await Directory(p.join(tempDir.path, 'skills')).create();
    });

    Future<({String stdout, String stderr})> run(List<String> args) async {
      final TestProcess process = await startCli([...args, '-d', skillsDir.path]);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      await process.shouldExit(1);
      return (stdout: stdout, stderr: stderr);
    }

    test('leaves the file and directory unchanged for directory "My Skill #1"', () async {
      final Directory skillDir = await createDummySkill(
        skillsDir,
        name: 'My Skill #1',
        skillContent: _skillMd(),
      );

      final (:String stdout, :String stderr) = await run(['--fix']);

      expect(stdout, isNot(contains('Renamed')));
      expect(stderr, contains('does not match the parent directory name'));
      expect(await File(p.join(skillDir.path, 'SKILL.md')).readAsString(), _skillMd());
      expect(skillsDir.listSync().map((e) => p.basename(e.path)), ['My Skill #1']);
    });

    test('sets name to an underscore directory name and keeps the directory', () async {
      final Directory skillDir = await createDummySkill(
        skillsDir,
        name: 'my_skill',
        skillContent: _skillMd(name: 'my-skill'),
      );

      final (stdout: String fixStdout, stderr: _) = await run(['--fix']);

      expect(fixStdout, isNot(contains('Renamed')));
      expect(
        await File(p.join(skillDir.path, 'SKILL.md')).readAsString(),
        _skillMd(name: 'my_skill'),
      );
      expect(skillsDir.listSync().map((e) => p.basename(e.path)), ['my_skill']);

      final (stdout: _, :String stderr) = await run([]);

      expect(stderr, isNot(contains('does not match the parent directory name')));
      expect(stderr, contains('contains invalid characters'));
    });
  });
}
