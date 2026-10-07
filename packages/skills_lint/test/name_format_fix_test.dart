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
    for (final (dirName, kind) in [
      ('my-skill', 'a valid skill name'),
      ('my_skill', 'an underscore'),
      ('My_Skill', 'uppercase letters and an underscore'),
      ('My-Skill', 'uppercase letters'),
      ('MySkill', 'uppercase letters'),
    ]) {
      test('sets name to directory name "$dirName", which has $kind', () async {
        expect(await _fix(dirName), _skillMd(name: dirName));
      });
    }

    // These load from YAML as the same string, but have characters other
    // than ASCII letters, digits, `_` and `-`.
    for (final dirName in ['my skill', 'a.b', 'café']) {
      test('leaves the file unchanged when directory "$dirName" has other characters', () async {
        expect(await _fix(dirName), _skillMd());
      });
    }

    // These would change meaning or fail to parse as a plain YAML scalar.
    for (final dirName in ['My Skill #1', 'a: b', '~', '[a]']) {
      test('leaves the file unchanged when directory "$dirName" is YAML syntax', () async {
        expect(await _fix(dirName), _skillMd());
      });
    }

    // These have only allowed characters, but a plain YAML scalar would load
    // as a number, boolean, null or list rather than this string.
    for (final dirName in [
      '123',
      '1e3',
      '0x1f',
      'null',
      'Null',
      'true',
      'TRUE',
      'false',
      '-',
      '---',
    ]) {
      test(
        'leaves the file unchanged when directory "$dirName" does not load as a string',
        () async {
          expect(await _fix(dirName), _skillMd());
        },
      );
    }
  });

  defineCliTests();
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  group('CLI --fix of invalid-skill-name', () {
    Future<({String stdout, String stderr})> run(Directory skillsDir, List<String> args) async {
      final TestProcess process = await startCli([...args, '-d', skillsDir.path]);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      await process.shouldExit(1);
      return (stdout: stdout, stderr: stderr);
    }

    List<String> dirNames(Directory skillsDir) =>
        skillsDir.listSync().map((e) => p.basename(e.path)).toList();

    test('leaves the file and directory unchanged for directory "My Skill #1"', () async {
      await withTempDir((skillsDir) async {
        final Directory skillDir = await createDummySkill(
          skillsDir,
          name: 'My Skill #1',
          skillContent: _skillMd(),
        );

        final (:String stdout, :String stderr) = await run(skillsDir, ['--fix']);

        expect(stdout, isNot(contains('Renamed')));
        expect(stderr, contains('does not match the parent directory name'));
        expect(await File(p.join(skillDir.path, 'SKILL.md')).readAsString(), _skillMd());
        expect(dirNames(skillsDir), ['My Skill #1']);
      });
    });

    test('sets name to an underscore directory name and keeps the directory', () async {
      await withTempDir((skillsDir) async {
        final Directory skillDir = await createDummySkill(
          skillsDir,
          name: 'my_skill',
          skillContent: _skillMd(name: 'my-skill'),
        );

        final (stdout: String fixStdout, stderr: _) = await run(skillsDir, ['--fix']);

        expect(fixStdout, isNot(contains('Renamed')));
        expect(
          await File(p.join(skillDir.path, 'SKILL.md')).readAsString(),
          _skillMd(name: 'my_skill'),
        );
        expect(dirNames(skillsDir), ['my_skill']);

        final (stdout: _, :String stderr) = await run(skillsDir, []);

        expect(stderr, isNot(contains('does not match the parent directory name')));
        expect(stderr, contains('contains invalid characters'));
      });
    });
  });
}
