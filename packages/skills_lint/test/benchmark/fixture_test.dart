// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../benchmark/src/fixture.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fixture_test.');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Returns the files under [root], keyed by `/`-separated relative path,
  /// with [root] replaced by `<root>` in their contents.
  Map<String, String> snapshot(String root) => {
    for (final File file in Directory(root).listSync(recursive: true).whereType<File>())
      p.split(p.relative(file.path, from: root)).join('/'): file.readAsStringSync().replaceAll(
        root,
        '<root>',
      ),
  };

  test('writes one directory with a SKILL.md per skill and a config file', () {
    final FixtureStats stats = writeFixture(tempDir.path, const FixtureSpec(skillCount: 12));

    final List<Directory> skills = Directory(
      p.join(tempDir.path, skillsDirectoryName),
    ).listSync().whereType<Directory>().toList();
    expect(skills, hasLength(12));
    for (final skill in skills) {
      expect(File(p.join(skill.path, 'SKILL.md')).existsSync(), isTrue, reason: skill.path);
    }
    expect(File(p.join(tempDir.path, 'skills_lint.yaml')).readAsStringSync(), fixtureConfig);
    expect(stats.skillCount, 12);
  });

  test('reports the number and total length of the files it wrote', () {
    final FixtureStats stats = writeFixture(tempDir.path, const FixtureSpec(skillCount: 20));

    final Map<String, String> files = snapshot(tempDir.path);
    expect(stats.fileCount, files.length);
    final int length = Directory(tempDir.path)
        .listSync(recursive: true)
        .whereType<File>()
        .fold(0, (sum, file) => sum + file.readAsStringSync().length);
    expect(stats.byteCount, length);
  });

  test('writes the same files for the same spec', () {
    final String a = p.join(tempDir.path, 'a');
    final String b = p.join(tempDir.path, 'b');
    writeFixture(a, const FixtureSpec(skillCount: 30));
    writeFixture(b, const FixtureSpec(skillCount: 30));

    expect(snapshot(a), snapshot(b));
  });

  test('writes different content for a different seed', () {
    final String a = p.join(tempDir.path, 'a');
    final String b = p.join(tempDir.path, 'b');
    writeFixture(a, const FixtureSpec(skillCount: 5));
    writeFixture(b, const FixtureSpec(skillCount: 5, seed: FixtureSpec.defaultSeed + 1));

    expect(snapshot(a), isNot(snapshot(b)));
  });

  test('plants one error in every invalidEvery-th skill, cycling through each kind', () {
    final int count = InvalidKind.values.length * 3;
    final FixtureStats stats = writeFixture(
      tempDir.path,
      FixtureSpec(skillCount: count, invalidEvery: 3),
    );

    expect(stats.invalidSkillCount, InvalidKind.values.length);
    final Map<String, String> files = snapshot(tempDir.path);
    String skillMd(int index) => files.entries
        .singleWhere(
          (e) =>
              e.key.startsWith('skills/skill-${index.toString().padLeft(4, '0')}-') &&
              e.key.endsWith('/SKILL.md'),
        )
        .value;

    int descriptionLength(int index) =>
        RegExp(r'description: >-\n  (.*)\n').firstMatch(skillMd(index))!.group(1)!.length;

    expect(skillMd(0), contains('-renamed\n'), reason: 'nameMismatch');
    expect(skillMd(3), matches(RegExp(r'[^ ] \n$')), reason: 'trailingWhitespace');
    expect(
      skillMd(6),
      matches(RegExp(r'\[Missing\]\(references/[a-z]+-\d+s\.md\)')),
      reason: 'brokenRelativeLink',
    );
    expect(descriptionLength(9), greaterThan(1024), reason: 'descriptionTooLong');
    expect(skillMd(12), contains('[Absolute](<root>'), reason: 'absoluteLink');
    expect(skillMd(1), isNot(contains('-renamed')));
    expect(descriptionLength(1), lessThanOrEqualTo(1024));
  });

  test('always makes the first skill invalid', () {
    final FixtureStats stats = writeFixture(
      tempDir.path,
      const FixtureSpec(skillCount: 1, invalidEvery: 1000),
    );

    expect(stats.invalidSkillCount, 1);
  });

  test('rejects invalidEvery below 1', () {
    expect(
      () => writeFixture(tempDir.path, const FixtureSpec(skillCount: 1, invalidEvery: 0)),
      throwsArgumentError,
    );
  });
}
