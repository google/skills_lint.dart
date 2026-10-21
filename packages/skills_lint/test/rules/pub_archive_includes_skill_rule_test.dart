// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Covers how pub-archive-includes-skill compares a skill with the files pub
// publishes. The file list is test data, so no test here runs pub.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/pub_archive.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/pub_archive_includes_skill_rule.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

const _skillName = 'my-pkg-setup';
const _skillFile = 'skills/$_skillName/SKILL.md';
const _referenceFile = 'skills/$_skillName/references/guide.md';

void main() {
  late Directory packageRoot;
  late Directory skillDir;

  setUp(() async {
    packageRoot = await Directory.systemTemp.createTemp('pub_archive_rule_test.');
    skillDir = Directory(p.join(packageRoot.path, 'skills', _skillName));
    await File(p.join(skillDir.path, 'references', 'guide.md')).create(recursive: true);
  });

  tearDown(() => packageRoot.delete(recursive: true));

  /// Runs the rule on a skill in [directory] whose body is [body], with
  /// [archive] as the files pub publishes.
  Future<List<ValidationError>> validate({
    required Directory directory,
    required String body,
    required PubArchive? archive,
  }) {
    final context = SkillContext(
      directory: directory,
      rawContent: '${buildFrontmatter(name: _skillName)}$body',
      pubArchive: archive,
    );
    return PubArchiveIncludesSkillRule(severity: .error).validate(context);
  }

  PubArchiveFiles archiveOf(Set<String> files) =>
      PubArchiveFiles(packageRoot: packageRoot.path, files: files);

  test('passes when SKILL.md and every linked file are published', () async {
    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: 'See [the guide](references/guide.md "Guide").\n',
      archive: archiveOf({_skillFile, _referenceFile}),
    );

    expect(errors, isEmpty);
  });

  test('reports a skill whose SKILL.md is not published', () async {
    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: 'See [the guide](references/guide.md).\n',
      archive: archiveOf({_referenceFile}),
    );

    expect(errors.map((e) => (e.ruleId, e.message)), [
      (
        PubArchiveIncludesSkillRule.ruleName,
        '$_skillFile is not in the package pub publishes, so `dart run skills@ get` '
            "won't install $_skillName. Check .pubignore and .gitignore.",
      ),
    ]);
  });

  test('reports a linked file that is not published, on the line of the link', () async {
    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: '\nSee [the guide](references/guide.md).\n',
      archive: archiveOf({_skillFile}),
    );

    // The frontmatter takes lines 1-4 and the body starts with a blank line,
    // so the link is on line 6.
    expect(errors.map((e) => (e.message, e.region?.startLine)), [
      (
        '$_referenceFile, linked from $_skillFile, is not in the package pub publishes, so the '
            'link is broken in installed copies of $_skillName. Check .pubignore and .gitignore.',
        6,
      ),
    ]);
  });

  test('ignores links that leave the package, are URLs, or point to no file', () async {
    final File outside = await File(p.join(packageRoot.parent.path, 'outside.md')).create();
    addTearDown(outside.delete);
    final String outsideLink = p.relative(outside.path, from: skillDir.path).replaceAll(r'\', '/');

    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body:
          '[outside]($outsideLink) [web](https://dart.dev) [anchor](#steps) '
          '[missing](references/missing.md)\n',
      archive: archiveOf({_skillFile}),
    );

    expect(errors, isEmpty);
  });

  test('passes a skill outside the skills directory, which pub does not install', () async {
    final Directory agentSkill = await Directory(
      p.join(packageRoot.path, '.agents', 'skills', _skillName),
    ).create(recursive: true);

    final List<ValidationError> errors = await validate(
      directory: agentSkill,
      body: '',
      archive: archiveOf({}),
    );

    expect(errors, isEmpty);
  });

  test('reports why the archive is unavailable', () async {
    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: '',
      archive: const PubArchiveUnavailable('dart is not on PATH'),
    );

    expect(errors.map((e) => e.message), ['dart is not on PATH']);
  });

  test('reports an error when no archive was provided', () async {
    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: '',
      archive: null,
    );

    expect(errors.single.message, contains('needs the list of files pub publishes'));
  });
}
