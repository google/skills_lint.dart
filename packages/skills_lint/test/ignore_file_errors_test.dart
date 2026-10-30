// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

void main() {
  defineCliTests();
}

/// End-to-end tests for an ignore file that contains malformed entries or is
/// not valid JSON. [main] calls this, and `compiled_test/cli_test.dart` calls
/// it again to run the same tests against the compiled binary.
void defineCliTests() {
  late Directory tempDir;
  late Directory skillsDir;
  late File ignoreFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ignore_errors_test.');
    skillsDir = await Directory(p.join(tempDir.path, 'skills')).create();
    // `my-skill` has an invalid name, which its ignore entry suppresses.
    final Directory mySkill = await Directory(p.join(skillsDir.path, 'my-skill')).create();
    await File(
      p.join(mySkill.path, 'SKILL.md'),
    ).writeAsString('${buildFrontmatter(name: 'Wrong', description: 'A skill.')}Body\n');
    final Directory other = await Directory(p.join(skillsDir.path, 'other')).create();
    await File(
      p.join(other.path, 'SKILL.md'),
    ).writeAsString('${buildFrontmatter(name: 'other', description: 'A skill.')}Body\n');
    ignoreFile = File(p.join(skillsDir.path, 'skills_lint_ignore.json'));
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  const malformedIgnores = '''
{"skills": {"my-skill": [{"rule_id": "invalid-skill-name", "file_name": "SKILL.md"}],
            "other": [{"rule_id": "description-too-long", "file_name": "SKILL.md"}, {"rule_id": "x"}]}}
''';

  test('applies the valid entries and reports the malformed one without failing', () async {
    await ignoreFile.writeAsString(malformedIgnores);

    final TestProcess process = await startCli(['-d', skillsDir.path]);
    final String stdout = (await process.stdout.rest.toList()).join('\n');
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(0);

    expect(stderr, contains('Ignore file error'));
    expect(stderr, contains(ignoreFile.path));
    expect(stderr, contains('skill "other", entry 2'));
    expect(stderr, contains('"file_name"'));
    // The valid entry for my-skill still suppresses its error.
    expect('$stdout\n$stderr', isNot(contains('does not match')));
  });

  test('reports each problem once when several skills share the file', () async {
    await ignoreFile.writeAsString(malformedIgnores);

    final TestProcess process = await startCli([
      '-s',
      p.join(skillsDir.path, 'my-skill'),
      '-s',
      p.join(skillsDir.path, 'other'),
      '--ignore-file',
      ignoreFile.path,
      '--generate-baseline',
    ]);
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(0);

    expect('skill "other", entry 2'.allMatches(stderr), hasLength(1));
    expect('Replacing ${ignoreFile.path}'.allMatches(stderr), hasLength(1));
  });

  test(
    '--generate-baseline replaces a file with malformed entries and says what it drops',
    () async {
      await ignoreFile.writeAsString(malformedIgnores);

      final TestProcess process = await startCli(['-d', skillsDir.path, '--generate-baseline']);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      await process.shouldExit(0);

      expect(
        stderr,
        contains(
          'Replacing ${ignoreFile.path} without carrying over 1 malformed entry (skill "other").',
        ),
      );
      final String written = ignoreFile.readAsStringSync();
      expect(written, contains('invalid-skill-name'));
      expect(written, contains('description-too-long'));
      expect(written, isNot(contains('"x"')));
      expect(File('${ignoreFile.path}.bak').existsSync(), isFalse);
    },
  );

  test('--fix --generate-baseline fixes a skill and keeps the valid entries', () async {
    await ignoreFile.writeAsString(malformedIgnores);
    // `fixable` has a name that --fix sets to its directory name.
    final Directory fixable = await Directory(p.join(skillsDir.path, 'fixable')).create();
    final fixableSkillMd = File(p.join(fixable.path, 'SKILL.md'));
    await fixableSkillMd.writeAsString(
      '${buildFrontmatter(name: 'wrong', description: 'A skill.')}Body\n',
    );

    final TestProcess process = await startCli([
      '-d',
      skillsDir.path,
      '--fix',
      '--generate-baseline',
    ]);
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(0);

    expect(stderr, contains('Replacing ${ignoreFile.path}'));
    expect(fixableSkillMd.readAsStringSync(), contains('name: fixable'));
    // The ignored skill is not fixed, and the valid entries survive.
    expect(
      File(p.join(skillsDir.path, 'my-skill', 'SKILL.md')).readAsStringSync(),
      contains('name: Wrong'),
    );
    final String written = ignoreFile.readAsStringSync();
    expect(written, contains('invalid-skill-name'));
    expect(written, contains('description-too-long'));
    expect(written, isNot(contains('"x"')));

    final TestProcess rerun = await startCli(['-d', skillsDir.path]);
    final String rerunStderr = (await rerun.stderr.rest.toList()).join('\n');
    await rerun.shouldExit(0);
    expect(rerunStderr, isEmpty);
  });

  test('--generate-baseline reports only the ignore files that had problems', () async {
    await ignoreFile.writeAsString(malformedIgnores);
    final Directory moreSkills = await Directory(p.join(tempDir.path, 'more')).create();
    final Directory third = await Directory(p.join(moreSkills.path, 'third')).create();
    await File(
      p.join(third.path, 'SKILL.md'),
    ).writeAsString('${buildFrontmatter(name: 'third', description: 'A skill.')}Body\n');
    final validIgnores = File(p.join(moreSkills.path, 'skills_lint_ignore.json'));
    await validIgnores.writeAsString('{"skills": {}}');

    final TestProcess process = await startCli([
      '-d',
      skillsDir.path,
      '-d',
      moreSkills.path,
      '--generate-baseline',
    ]);
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(0);

    expect(stderr, contains('Replacing ${ignoreFile.path}'));
    expect(stderr, isNot(contains('Replacing ${validIgnores.path}')));
  });

  test('reports an ignore file that is not valid JSON without failing', () async {
    // The file's entries are lost, so my-skill's invalid name is reported.
    await ignoreFile.writeAsString('{ not json');

    final TestProcess process = await startCli(['-d', skillsDir.path]);
    final String stdout = (await process.stdout.rest.toList()).join('\n');
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(1);

    expect(stderr, contains(ignoreFile.path));
    expect(stderr, contains('not valid JSON'));
    expect('$stdout\n$stderr', contains('does not match the parent directory name'));
  });

  test('--generate-baseline replaces an ignore file that is not valid JSON', () async {
    await ignoreFile.writeAsString('{ not json');

    final TestProcess process = await startCli(['-d', skillsDir.path, '--generate-baseline']);
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(0);

    expect(
      stderr,
      contains('Replacing ${ignoreFile.path} without carrying over its unreadable contents.'),
    );
    expect(ignoreFile.readAsStringSync(), contains('invalid-skill-name'));
  });
}
