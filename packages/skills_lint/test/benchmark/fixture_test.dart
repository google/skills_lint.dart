// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/rule_registry.dart';
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

  group('invalidKindsFor', () {
    test('pairs each kind with the next one in the cycle', () {
      expect(invalidKindsFor(0), {InvalidKind.nameMismatch, InvalidKind.trailingWhitespace});
      expect(invalidKindsFor(InvalidKind.values.length), invalidKindsFor(0));
    });

    test('never combines missingSkillMd with another kind', () {
      for (var i = 0; i < InvalidKind.values.length; i++) {
        final Set<InvalidKind> kinds = invalidKindsFor(i);
        if (kinds.contains(InvalidKind.missingSkillMd)) {
          expect(kinds, {InvalidKind.missingSkillMd});
        }
      }
    });
  });

  test('every registered rule reports at least once on the fixture', () async {
    final int count = InvalidKind.values.length * 3;
    final FixtureStats stats = writeFixture(
      tempDir.path,
      FixtureSpec(skillCount: count, invalidEvery: 3),
    );
    expect(stats.invalidSkillCount, InvalidKind.values.length);

    final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
      p.absolute('bin', 'skills_lint.dart'),
      '--format',
      'json',
    ], workingDirectory: tempDir.path);
    final List<Map<String, Object?>> results = (jsonDecode(result.stdout as String) as List)
        .cast<Map<String, Object?>>();

    final Set<String> reported = {
      for (final skill in results)
        for (final error in (skill['validationErrors']! as List).cast<Map<String, Object?>>())
          error['ruleId']! as String,
    };
    expect(reported, {for (final check in RuleRegistry.allChecks) check.name});
    final int skillsWithTwoErrors = results
        .where((skill) => (skill['validationErrors']! as List).length >= 2)
        .length;
    expect(skillsWithTwoErrors, greaterThan(0));
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
