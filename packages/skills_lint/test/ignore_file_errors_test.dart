// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

/// End-to-end tests for an ignore file that contains malformed entries or is
/// not valid JSON.
void main() {
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
    await process.shouldExit(1);

    expect('skill "other", entry 2'.allMatches(stderr), hasLength(1));
    expect('did not write the baseline'.allMatches(stderr), hasLength(1));
  });

  test('--generate-baseline refuses to overwrite a file with malformed entries', () async {
    await ignoreFile.writeAsString(malformedIgnores);

    final TestProcess process = await startCli(['-d', skillsDir.path, '--generate-baseline']);
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(1);

    expect(ignoreFile.readAsStringSync(), malformedIgnores);
    expect(stderr, contains('did not write the baseline to ${ignoreFile.path}'));
  });

  test('--fix --generate-baseline refuses to overwrite a file with malformed entries', () async {
    await ignoreFile.writeAsString(malformedIgnores);

    final TestProcess process = await startCli([
      '-d',
      skillsDir.path,
      '--fix',
      '--generate-baseline',
    ]);
    await process.stderr.rest.toList();
    await process.shouldExit(1);

    expect(ignoreFile.readAsStringSync(), malformedIgnores);
  });

  test('-s with --generate-baseline refuses to overwrite a malformed custom file', () async {
    await ignoreFile.writeAsString(malformedIgnores);

    final TestProcess process = await startCli([
      '-s',
      p.join(skillsDir.path, 'other'),
      '--ignore-file',
      ignoreFile.path,
      '--generate-baseline',
    ]);
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(1);

    expect(ignoreFile.readAsStringSync(), malformedIgnores);
    expect(stderr, contains('skill "other", entry 2'));
  });

  test('reports an ignore file that is not valid JSON without failing', () async {
    // The file's entries are lost, so my-skill's invalid name is reported.
    await ignoreFile.writeAsString('{ not json');

    final TestProcess process = await startCli(['-d', skillsDir.path]);
    final String stderr = (await process.stderr.rest.toList()).join('\n');
    await process.shouldExit(1);

    expect(stderr, contains(ignoreFile.path));
    expect(stderr, contains('not valid JSON'));
  });

  test('--generate-baseline leaves an ignore file that is not valid JSON unchanged', () async {
    await ignoreFile.writeAsString('{ not json');

    final TestProcess process = await startCli(['-d', skillsDir.path, '--generate-baseline']);
    await process.stderr.rest.toList();
    await process.shouldExit(1);

    expect(ignoreFile.readAsStringSync(), '{ not json');
  });
}
