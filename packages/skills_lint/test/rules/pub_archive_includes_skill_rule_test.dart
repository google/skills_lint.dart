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
const _howToFix =
    'Run `dart pub publish --dry-run` to list the files pub publishes, and check .pubignore '
    'and .gitignore.';

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
        '$_skillFile is not in the package pub publishes, so the published package has no '
            '$_skillName skill. $_howToFix',
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
        '$_referenceFile, linked from $_skillFile, is not in the package pub publishes. '
            '$_howToFix',
        6,
      ),
    ]);
  });

  test('reports one diagnostic for a directory that pub leaves out entirely', () async {
    final List<String> guides = [for (var i = 0; i < 12; i++) 'references/guide$i.md'];
    for (final guide in guides) {
      await File(p.join(skillDir.path, guide)).create(recursive: true);
    }

    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: '\n${guides.map((g) => '[$g]($g)').join('\n')}\n',
      archive: archiveOf({_skillFile}),
    );

    expect(errors.map((e) => (e.message, e.region?.startLine)), [
      (
        'skills/$_skillName/references/ is not in the package pub publishes, so neither are '
            'the 12 files $_skillFile links to in it. $_howToFix',
        6,
      ),
    ]);
  });

  test('lists each missing file when its directory is partly published', () async {
    await File(p.join(skillDir.path, 'references', 'other.md')).create();

    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: '[a](references/guide.md) [b](references/other.md)\n',
      archive: archiveOf({_skillFile, 'skills/$_skillName/references/kept.md'}),
    );

    expect(errors.map((e) => e.message.split(',').first), [
      _referenceFile,
      'skills/$_skillName/references/other.md',
    ]);
  });

  group('a link that leaves the skill but stays in the package', () {
    setUp(() => File(p.join(packageRoot.path, 'README.md')).create());

    test('passes when pub publishes the target', () async {
      final List<ValidationError> errors = await validate(
        directory: skillDir,
        body: '[readme](../../README.md)\n',
        archive: archiveOf({_skillFile, 'README.md'}),
      );

      expect(errors, isEmpty);
    });

    test('is reported when pub leaves the target out', () async {
      final List<ValidationError> errors = await validate(
        directory: skillDir,
        body: '[readme](../../README.md)\n',
        archive: archiveOf({_skillFile}),
      );

      expect(errors.map((e) => e.message), [
        'README.md, linked from $_skillFile, is not in the package pub publishes. $_howToFix',
      ]);
    });
  });

  test('reports a link to a file outside the package', () async {
    final File outside = await File(p.join(packageRoot.parent.path, 'outside.md')).create();
    addTearDown(outside.delete);
    final String outsideLink = p.relative(outside.path, from: skillDir.path).replaceAll(r'\', '/');
    final String outsideFile = p
        .relative(outside.path, from: packageRoot.path)
        .replaceAll(r'\', '/');

    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: '[outside]($outsideLink)\n',
      archive: archiveOf({_skillFile}),
    );

    expect(
      errors.single.message,
      startsWith('$outsideFile, linked from $_skillFile, is outside the package'),
    );
  });

  test('ignores links that are URLs or point to no file', () async {
    final List<ValidationError> errors = await validate(
      directory: skillDir,
      body: '[web](https://dart.dev) [anchor](#steps) [missing](references/missing.md)\n',
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

  test('passes a skill outside the skills directory when the archive is unavailable', () async {
    final Directory agentSkill = await Directory(
      p.join(packageRoot.path, '.agents', 'skills', _skillName),
    ).create(recursive: true);

    final List<ValidationError> errors = await validate(
      directory: agentSkill,
      body: '',
      archive: PubArchiveUnavailable('dart is not on PATH', packageRoot: packageRoot.path),
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
