// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Runs the CLI with --pub-archive-includes-skill on a package whose
// .pubignore drops a skill, with the real `dart pub publish`. This is the
// only test that checks the rule against pub's own .pubignore handling and
// the hidden --to-archive option.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/rules/pub_archive_includes_skill_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

void main() {
  defineCliTests();
}

/// Defines the tests that run the CLI, so `compiled_test/` can run them
/// against the compiled binary too.
void defineCliTests() {
  test('reports a skill that .pubignore drops from the published package', () async {
    final Directory packageDir = await Directory.systemTemp.createTemp('pub_archive_cli_test.');
    addTearDown(() => packageDir.delete(recursive: true));
    await File(p.join(packageDir.path, 'pubspec.yaml')).writeAsString('''
name: my_pkg
version: 1.0.0
description: A package with skills, for a skills_lint test.
environment:
  sdk: ^3.12.0
''');
    await File(p.join(packageDir.path, '.pubignore')).writeAsString('/skills/my-pkg-dropped/\n');
    final skillsDir = Directory(p.join(packageDir.path, 'skills'));
    for (final name in ['my-pkg-dropped', 'my-pkg-kept']) {
      await createDummySkill(
        skillsDir,
        name: name,
        skillContent: buildFrontmatter(name: name),
      );
    }

    final TestProcess process = await startCli([
      '--${PubArchiveIncludesSkillRule.ruleName}',
      '--skills-directory',
      'skills',
    ], workingDirectory: packageDir.path);

    final String errors = (await process.stderrStream().toList()).join('\n');
    expect(
      errors,
      allOf(
        contains(
          'skills/my-pkg-dropped/SKILL.md is not in the package pub publishes, so the published '
          'package has no my-pkg-dropped skill.',
        ),
        isNot(contains('skills/my-pkg-kept/SKILL.md is not')),
      ),
    );
    await process.shouldExit(1);
  });
}
