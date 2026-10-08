// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/name_format_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

/// A `SKILL.md` whose frontmatter sets `name` to [name].
String _skillMd({String name = 'Old_Name'}) => '${buildFrontmatter(name: name)}body\n';

Future<String> _fix(String dirName) =>
    NameFormatRule().fix('SKILL.md', _skillMd(), Directory(p.join('skills', dirName)));

void main() {
  group('NameFormatRule.isValidSkillName', () {
    for (final String name in [
      'my-skill',
      'a',
      'a1-b2',
      'a' * NameFormatRule.maxNameLength,
      'a' * (NameFormatRule.maxNameLength + 1),
      'my_skill',
      'My-Skill',
      '-foo',
      'foo-',
      'a--b',
      '-',
      '---',
      'my skill',
      'café',
    ]) {
      test('agrees with validate for "$name"', () async {
        final SkillContext context = createTestSkillContext(
          directory: Directory(p.join('skills', name)),
          name: "'$name'",
        );

        final List<ValidationError> errors = await NameFormatRule().validate(context);

        expect(NameFormatRule.isValidSkillName(name), errors.isEmpty);
      });
    }
  });

  group('NameFormatRule.nameText', () {
    for (final (String name, String text) in [
      ('123', '123'),
      ('true', 'true'),
      ('1e3', '1e3'),
      ('0x1f', '0x1f'),
      ("'123'", '123'),
    ]) {
      test('reads name: $name as "$text"', () {
        final SkillContext context = createTestSkillContext(
          directory: Directory(p.join('skills', 'my-skill')),
          name: name,
        );

        expect(NameFormatRule.nameText(NameFormatRule.getNameNode(context.parsedYaml!)), text);
      });
    }

    test('trims the trailing spaces of a scalar that ends the document', () {
      expect(NameFormatRule.nameText(loadYamlNode('1e3   ')), '1e3');
    });

    for (final name in ['1e3', '0x1f']) {
      test('lets validate pass name: $name in directory "$name"', () async {
        final SkillContext context = createTestSkillContext(
          directory: Directory(p.join('skills', name)),
          name: name,
        );

        expect(await NameFormatRule().validate(context), isEmpty);
      });
    }
  });

  group('NameFormatRule.fix', () {
    for (final String dirName in ['my-skill', 'a1-b2', 'a' * NameFormatRule.maxNameLength]) {
      test('sets name to directory name "$dirName", a valid skill name', () async {
        expect(await _fix(dirName), _skillMd(name: dirName));
      });
    }

    for (final String dirName in [
      'My-Skill',
      '-foo',
      'foo-',
      'a--b',
      '-',
      '---',
      'a' * (NameFormatRule.maxNameLength + 1),
      'My Skill #1',
      'a: b',
      '~',
      '[a]',
    ]) {
      test(
        'leaves the file unchanged when directory "$dirName" is not a valid skill name',
        () async {
          expect(await _fix(dirName), _skillMd());
        },
      );
    }

    // Valid skill names that a plain YAML scalar would load as a number,
    // boolean or null rather than this string.
    for (final dirName in ['123', '1e3', '0x1f', 'null', 'true', 'false']) {
      test('sets name to directory name "$dirName" in double quotes', () async {
        expect(await _fix(dirName), _skillMd(name: '"$dirName"'));
      });
    }

    for (final quote in ['"', "'"]) {
      for (final dirName in ['my-skill', '123']) {
        test('keeps the $quote quotes around name when setting it to "$dirName"', () async {
          final String fixed = await NameFormatRule().fix(
            'SKILL.md',
            _skillMd(name: '${quote}old$quote'),
            Directory(p.join('skills', dirName)),
          );

          expect(fixed, _skillMd(name: '$quote$dirName$quote'));
        });
      }
    }
  });

  defineCliTests();
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  group('CLI --fix of invalid-skill-name', () {
    Future<({String stdout, String stderr})> run(
      Directory skillsDir,
      List<String> args, {
      int exitCode = 1,
    }) async {
      final TestProcess process = await startCli([...args, '-d', skillsDir.path]);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      await process.shouldExit(exitCode);
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

    test('leaves the file and directory unchanged for an underscore directory', () async {
      await withTempDir((skillsDir) async {
        final Directory skillDir = await createDummySkill(
          skillsDir,
          name: 'my_skill',
          skillContent: _skillMd(name: 'my-skill'),
        );

        final (:String stdout, :String stderr) = await run(skillsDir, ['--fix']);

        expect(stdout, isNot(contains('Renamed')));
        expect(stderr, contains('does not match the parent directory name'));
        expect(
          await File(p.join(skillDir.path, 'SKILL.md')).readAsString(),
          _skillMd(name: 'my-skill'),
        );
        expect(dirNames(skillsDir), ['my_skill']);
      });
    });

    test('writes a quoted name and keeps the directory for directory "123"', () async {
      await withTempDir((skillsDir) async {
        final Directory skillDir = await createDummySkill(
          skillsDir,
          name: '123',
          skillContent: _skillMd(),
        );

        final (:String stdout, stderr: _) = await run(skillsDir, ['--fix'], exitCode: 0);

        expect(stdout, isNot(contains('Renamed')));
        expect(
          await File(p.join(skillDir.path, 'SKILL.md')).readAsString(),
          _skillMd(name: '"123"'),
        );
        expect(dirNames(skillsDir), ['123']);
      });
    });

    for (final name in ['123', 'true']) {
      test('passes and leaves the file unchanged for name: $name in directory "$name"', () async {
        await withTempDir((skillsDir) async {
          final Directory skillDir = await createDummySkill(
            skillsDir,
            name: name,
            skillContent: _skillMd(name: name),
          );

          final (:String stdout, :String stderr) = await run(skillsDir, ['--fix'], exitCode: 0);

          expect(stdout, isNot(contains('Applied fixes')));
          expect(stderr, isEmpty);
          expect(
            await File(p.join(skillDir.path, 'SKILL.md')).readAsString(),
            _skillMd(name: name),
          );
          expect(dirNames(skillsDir), [name]);
        });
      });
    }
  });
}
