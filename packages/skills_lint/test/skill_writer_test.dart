// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests of [SkillWriter], which does all of the file I/O for `--fix`.
///
/// Each failure case checks the [ApplyResult] type, that the reason names
/// what blocked the write, and that the skill on disk is unchanged. Each
/// success case checks the directory listing and the written content.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/reporters/text_reporter.dart';
import 'package:skills_lint/src/write/skill_writer.dart';
import 'package:skills_lint/src/write/write_boundary.dart';
import 'package:test/test.dart';

/// No boundary, for the tests that are not about one.
const none = WriteBoundary.none();

void main() {
  late Directory root;
  late Directory skills;
  late StringBuffer err;
  late SkillWriter writer;

  setUp(() async {
    root = Directory(
      (await Directory.systemTemp.createTemp('skill_writer_test.')).resolveSymbolicLinksSync(),
    );
    addTearDown(() => root.delete(recursive: true));
    skills = Directory(p.join(root.path, 'skills'))..createSync();
    err = StringBuffer();
    writer = SkillWriter(TextReporter(out: StringBuffer(), err: err));
  });

  /// Creates a skill directory named [name] that holds a SKILL.md.
  Directory createSkill(String name) {
    final dir = Directory(p.join(skills.path, name))..createSync();
    File(p.join(dir.path, 'SKILL.md')).writeAsStringSync('before\n');
    return dir;
  }

  List<String> listing() => [for (final e in skills.listSync()) p.basename(e.path)]..sort();

  String skillMd(String name) => File(p.join(skills.path, name, 'SKILL.md')).readAsStringSync();

  test('writes in place when the name does not change', () async {
    final Directory dir = createSkill('foo');

    final ApplyResult result = await writer.apply(dir, 'after\n', 'foo', none);

    expect(result, isA<Applied>().having((r) => r.renamed, 'renamed', isFalse));
    expect(listing(), ['foo']);
    expect(skillMd('foo'), 'after\n');
  });

  test('renames, then writes into the renamed directory', () async {
    final Directory dir = createSkill('foo');

    expect(writer.preflight(dir, 'bar-foo', none), isA<Applied>());
    final ApplyResult result = await writer.apply(dir, 'after\n', 'bar-foo', none);

    expect(
      result,
      isA<Applied>()
          .having((r) => r.renamed, 'renamed', isTrue)
          .having((r) => p.basename(r.dir.path), 'dir', 'bar-foo'),
    );
    expect(listing(), ['bar-foo']);
    expect(skillMd('bar-foo'), 'after\n');
  });

  test('renames a directory whose name differs only in case', () async {
    // On a case-insensitive file system, `bar-x` already "exists" as `Bar-x`.
    final Directory dir = createSkill('Bar-x');

    expect(writer.preflight(dir, 'bar-x', none), isA<Applied>());
    final ApplyResult result = await writer.apply(dir, 'after\n', 'bar-x', none);

    expect(result, isA<Applied>().having((r) => r.renamed, 'renamed', isTrue));
    expect(listing(), ['bar-x']);
    expect(skillMd('bar-x'), 'after\n');
  });

  group('blocks the rename and writes nothing', () {
    test('when the target directory exists', () async {
      createSkill('bar-foo');
      final Directory dir = createSkill('foo');

      final Matcher blocked = isA<RenameBlocked>().having(
        (r) => r.reason,
        'reason',
        contains('bar-foo already exists'),
      );
      expect(writer.preflight(dir, 'bar-foo', none), blocked);
      expect(await writer.apply(dir, 'after\n', 'bar-foo', none), blocked);
      expect(listing(), ['bar-foo', 'foo']);
      expect(skillMd('foo'), 'before\n');
      expect(err.toString(), contains('bar-foo'));
    });

    test('when the target differs only in case from another directory', () async {
      // `Bar-foo` and `bar-foo` are one name on a case-insensitive file
      // system, and two names elsewhere. Either way the rename can't land on
      // `bar-foo` without touching the other skill, so the test creates the
      // clash as `bar-foo` itself when the file system is case-sensitive.
      createSkill('Bar-foo');
      final bool caseSensitive = !Directory(p.join(skills.path, 'bar-foo')).existsSync();
      if (caseSensitive) {
        createSkill('bar-foo');
      }
      final Directory dir = createSkill('foo');

      expect(await writer.apply(dir, 'after\n', 'bar-foo', none), isA<RenameBlocked>());
      expect(skillMd('foo'), 'before\n');
    });

    test('when the parent directory is read-only', () async {
      final Directory dir = createSkill('foo');
      await Process.run('chmod', ['555', skills.path]);
      addTearDown(() => Process.run('chmod', ['755', skills.path]));

      // preflight doesn't try the rename, so it can't see a permission
      // error.
      expect(writer.preflight(dir, 'bar-foo', none), isA<Applied>());
      final ApplyResult result = await writer.apply(dir, 'after\n', 'bar-foo', none);

      expect(
        result,
        isA<RenameBlocked>()
            .having((r) => r.error, 'error', isA<FileSystemException>())
            .having((r) => r.reason, 'reason', isNotEmpty),
      );
      expect(listing(), ['foo']);
      expect(skillMd('foo'), 'before\n');
      expect(err.toString(), contains('bar-foo'));
    }, skip: Platform.isWindows ? 'uses the POSIX chmod command' : null);
  });

  group('refuses to write outside the boundary and writes nothing', () {
    late WriteBoundary boundary;

    setUp(() => boundary = WriteBoundary(skills.path));

    Future<void> expectRefusedName(String crafted, {required String expectedReason}) async {
      final Directory dir = createSkill('foo');

      expect(writer.preflight(dir, crafted, boundary), isA<WriteRefused>());
      expect(await writer.apply(dir, 'after\n', crafted, boundary), isA<WriteRefused>());

      expect(listing(), ['foo']);
      expect(skillMd('foo'), 'before\n');
      expect(Directory(p.join(root.path, 'escaped')).existsSync(), isFalse);
      expect(err.toString(), contains("'$crafted': the skill name '$crafted' $expectedReason"));
    }

    test('for a parent-relative path "../escaped"', () async {
      await expectRefusedName('../escaped', expectedReason: 'contains a path separator');
    });

    test('for a platform parent-relative path', () async {
      await expectRefusedName(p.join('..', 'escaped'), expectedReason: 'contains a path separator');
    });

    test('for an absolute path', () async {
      await expectRefusedName(
        p.join(Directory.systemTemp.path, 'escaped'),
        expectedReason: 'contains a path separator',
      );
    });

    test('for ".."', () async {
      await expectRefusedName('..', expectedReason: 'refers to the current or parent directory');
    });

    test('for a nested path "a/b"', () async {
      await expectRefusedName('a/b', expectedReason: 'contains a path separator');
    });

    test('for a skill directory that links outside the boundary', () async {
      final real = Directory(p.join(root.path, 'real'))..createSync();
      File(p.join(real.path, 'SKILL.md')).writeAsStringSync('before\n');
      final link = Link(p.join(skills.path, 'foo'))..createSync(real.path);

      final ApplyResult result = await writer.apply(
        Directory(link.path),
        'after\n',
        'foo',
        boundary,
      );

      expect(result, isA<WriteRefused>());
      expect(File(p.join(real.path, 'SKILL.md')).readAsStringSync(), 'before\n');
      expect(err.toString(), contains("resolves to '${p.join(real.path, 'SKILL.md')}'"));
    });

    test('accepts a rename inside the boundary', () async {
      final Directory dir = createSkill('foo');

      expect(writer.preflight(dir, 'bar-foo', boundary), isA<Applied>());
      expect(await writer.apply(dir, 'after\n', 'bar-foo', boundary), isA<Applied>());

      expect(listing(), ['bar-foo']);
    });

    test(
      'writes SKILL.md in place when an existing directory name contains a backslash',
      () async {
        const nameWithBackslash = r'foo\bar';
        final Directory dir = createSkill(nameWithBackslash);

        expect(writer.preflight(dir, nameWithBackslash, boundary), isA<Applied>());
        expect(await writer.apply(dir, 'after\n', nameWithBackslash, boundary), isA<Applied>());

        expect(skillMd(nameWithBackslash), 'after\n');
      },
      // Skipped on Windows: `\` is a path separator on Windows, so a directory
      // basename cannot contain `\`.
      testOn: '!windows',
    );
  });

  test('undoes the rename when the write fails after it', () async {
    final Directory dir = createSkill('foo');
    final file = File(p.join(dir.path, 'SKILL.md'));
    await Process.run('chmod', ['444', file.path]);
    addTearDown(() => Process.run('chmod', ['644', p.join(skills.path, 'foo', 'SKILL.md')]));

    final ApplyResult result = await writer.apply(dir, 'after\n', 'bar-foo', none);

    expect(result, isA<WriteFailed>().having((r) => p.basename(r.dir.path), 'dir', 'foo'));
    expect(listing(), ['foo']);
    expect(skillMd('foo'), 'before\n');
  }, skip: Platform.isWindows ? 'uses the POSIX chmod command' : null);

  test('reports a write error and leaves the skill unchanged', () async {
    final Directory dir = createSkill('foo');
    final file = File(p.join(dir.path, 'SKILL.md'));
    await Process.run('chmod', ['444', file.path]);
    addTearDown(() => Process.run('chmod', ['644', file.path]));

    final ApplyResult result = await writer.apply(dir, 'after\n', 'foo', none);

    expect(result, isA<WriteFailed>().having((r) => r.error, 'error', isA<FileSystemException>()));
    expect(skillMd('foo'), 'before\n');
    expect(err.toString(), contains('foo'));
  }, skip: Platform.isWindows ? 'uses the POSIX chmod command' : null);
}
