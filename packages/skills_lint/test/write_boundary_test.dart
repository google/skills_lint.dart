// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests of [WriteBoundary], which decides whether skills_lint may write a
/// path, on real files and symlinks.
///
/// The symlink tests fail, rather than skip, where a symlink can't be
/// created, so CI on Windows can't pass without running them.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/write/write_boundary.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory inside;
  late Directory outside;

  setUp(() async {
    root = Directory(
      (await Directory.systemTemp.createTemp('write_boundary_test.')).resolveSymbolicLinksSync(),
    );
    addTearDown(() => root.delete(recursive: true));
    inside = Directory(p.join(root.path, 'inside'))..createSync();
    outside = Directory(p.join(root.path, 'outside'))..createSync();
  });

  LintTargetConfig parseDirectoryTarget(String path, {required Directory configDir}) =>
      ConfigParser.parse(
        'skills_lint:\n  directories:\n    - path: "${path.replaceAll(r'\', r'\\')}"\n',
        configSource: ConfigSource.directory(configDir.path),
      ).directoryConfigs.single;

  LintTargetConfig parseSkillTarget(String path, {required Directory configDir}) =>
      ConfigParser.parse(
        'skills_lint:\n  individual_skills:\n    - path: "${path.replaceAll(r'\', r'\\')}"\n',
        configSource: ConfigSource.directory(configDir.path),
      ).individualSkillConfigs.single;

  group('refusal', () {
    test('accepts a file inside, and one that does not exist yet', () {
      final boundary = WriteBoundary(inside.path);
      File(p.join(inside.path, 'a.json')).createSync();

      expect(boundary.refusal(p.join(inside.path, 'a.json')), isNull);
      expect(boundary.refusal(p.join(inside.path, 'new', 'b.json')), isNull);
    });

    test('refuses a path outside, and the boundary itself', () {
      final boundary = WriteBoundary(inside.path);

      expect(boundary.refusal(p.join(outside.path, 'a.json')), "it is outside '${inside.path}'");
      expect(boundary.refusal(inside.path), isNotNull);
    });

    test('refuses a path through a symlink that leads outside', () {
      final boundary = WriteBoundary(inside.path);
      Link(p.join(inside.path, 'link')).createSync(outside.path);
      final String path = p.join(inside.path, 'link', 'a.json');

      expect(
        boundary.refusal(path),
        "it resolves to '${p.join(outside.path, 'a.json')}', outside '${inside.path}'",
      );
    });

    test('refuses a dangling symlink whose target is outside', () {
      final boundary = WriteBoundary(inside.path);
      final String link = p.join(inside.path, 'ignore.json');
      Link(link).createSync(p.join(outside.path, 'missing.json'));

      expect(boundary.refusal(link), contains(p.join(outside.path, 'missing.json')));
    });

    test('resolves a link before the .. that follows it', () {
      final boundary = WriteBoundary(inside.path);
      final deep = Directory(p.join(outside.path, 'deep'))..createSync();
      Link(p.join(inside.path, 'l')).createSync(deep.path);

      // As text, `l/../new.json` is inside; on disk it is `outside/new.json`.
      expect(
        boundary.refusal(p.join(inside.path, 'l', '..', 'new.json')),
        contains(p.join(outside.path, 'new.json')),
      );
    });

    test('accepts a symlink that stays inside', () {
      final boundary = WriteBoundary(inside.path);
      final target = Directory(p.join(inside.path, 'real'))..createSync();
      Link(p.join(inside.path, 'alias')).createSync(target.path);

      expect(boundary.refusal(p.join(inside.path, 'alias', 'SKILL.md')), isNull);
    });

    test('compares real paths when the boundary is reached through a symlink', () {
      final String linkedRoot = p.join(outside.path, 'linked');
      Link(linkedRoot).createSync(inside.path);

      expect(WriteBoundary(linkedRoot).refusal(p.join(inside.path, 'a.json')), isNull);
    });

    test('accepts an allowed directory itself, and paths inside it', () {
      final boundary = WriteBoundary(inside.path, allowed: [outside.path]);

      expect(boundary.refusal(outside.path), isNull);
      expect(boundary.refusal(p.join(outside.path, 'a.json')), isNull);
      expect(boundary.refusal(p.join(root.path, 'other.json')), isNotNull);
    });

    test('accepts anything without a boundary', () {
      expect(const WriteBoundary.none().refusal(p.join(outside.path, 'a.json')), isNull);
    });
  });

  group('forSkillsDirectory', () {
    test('is the directory when the configuration directory holds it', () {
      final LintTargetConfig declaredBy = parseDirectoryTarget(inside.path, configDir: root);
      final boundary = WriteBoundary.forSkillsDirectory(inside.path, declaredBy: declaredBy);

      expect(boundary.refusal(p.join(inside.path, 'a', 'SKILL.md')), isNull);
      expect(boundary.refusal(p.join(outside.path, 'a', 'SKILL.md')), isNotNull);
    });

    test('refuses every write when the directory is outside the configuration directory', () {
      final LintTargetConfig declaredBy = parseDirectoryTarget(outside.path, configDir: inside);
      final boundary = WriteBoundary.forSkillsDirectory(outside.path, declaredBy: declaredBy);

      expect(boundary.refusal(p.join(outside.path, 'a', 'SKILL.md')), isNotNull);
    });
  });

  group('forSkill', () {
    test('lets the skill be renamed next to where it is', () {
      final skill = Directory(p.join(inside.path, 'foo'))..createSync();
      final boundary = WriteBoundary.forSkill(skill.path);

      expect(boundary.refusal(p.join(skill.path, 'SKILL.md')), isNull);
      expect(boundary.refusal(p.join(inside.path, 'bar')), isNull);
    });

    test('refuses every write when the skill is outside the configuration directory', () {
      final skill = Directory(p.join(outside.path, 'foo'))..createSync();
      final LintTargetConfig declaredBy = parseSkillTarget(skill.path, configDir: inside);
      final boundary = WriteBoundary.forSkill(skill.path, declaredBy: declaredBy);

      expect(boundary.refusal(p.join(skill.path, 'SKILL.md')), isNotNull);
    });
  });

  group('directoryNameRefusal', () {
    test('accepts simple skill names', () {
      expect(WriteBoundary.directoryNameRefusal('foo'), isNull);
      expect(WriteBoundary.directoryNameRefusal('foo-bar'), isNull);
      expect(WriteBoundary.directoryNameRefusal('a.b'), isNull);
    });

    test('refuses an empty name', () {
      expect(WriteBoundary.directoryNameRefusal(''), 'the skill name is empty');
    });

    test('refuses "." and ".."', () {
      expect(
        WriteBoundary.directoryNameRefusal('.'),
        "the skill name '.' refers to the current or parent directory",
      );
      expect(
        WriteBoundary.directoryNameRefusal('..'),
        "the skill name '..' refers to the current or parent directory",
      );
    });

    test('refuses names containing path separators or root prefixes', () {
      expect(WriteBoundary.directoryNameRefusal('../x'), contains('contains a path separator'));
      expect(WriteBoundary.directoryNameRefusal('a/b'), contains('contains a path separator'));
      expect(WriteBoundary.directoryNameRefusal(r'a\b'), contains('contains a path separator'));
      expect(WriteBoundary.directoryNameRefusal('/tmp/x'), contains('contains a path separator'));
      expect(WriteBoundary.directoryNameRefusal(r'C:\x'), contains('contains a path separator'));
    });
  });
}
