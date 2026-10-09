// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/checksums.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:test/test.dart';

/// SHA-256 of the three bytes `abc`, from FIPS 180-2 appendix B.1.
const String _abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('checksums_test.');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  File write(String name, String contents) =>
      File(p.join(dir.path, name))..writeAsStringSync(contents);

  List<String> names() =>
      [for (final FileSystemEntity entity in dir.listSync()) p.basename(entity.path)]..sort();

  test('writeChecksum writes "<hash>  <name>" next to the file', () {
    final File part = writeChecksum(write('skills_lint-linux-x64.tar.gz', 'abc'));
    expect(p.basename(part.path), 'skills_lint-linux-x64.tar.gz.sha256');
    expect(part.readAsStringSync(), '$_abcSha256  skills_lint-linux-x64.tar.gz\n');
  });

  group('mergeChecksums', () {
    test('writes SHA256SUMS sorted by name and removes the parts', () {
      writeChecksum(write('skills_lint-macos-x64.tar.gz', 'abc'));
      writeChecksum(write('skills_lint-linux-x64.tar.gz', 'def'));
      final File sums = mergeChecksums(dir);
      expect(p.basename(sums.path), sha256SumsName);
      final List<String> lines = sums.readAsLinesSync();
      expect(lines.map((line) => line.split('  ').last), [
        'skills_lint-linux-x64.tar.gz',
        'skills_lint-macos-x64.tar.gz',
      ]);
      expect(lines.last, '$_abcSha256  skills_lint-macos-x64.tar.gz');
      expect(names(), [
        sha256SumsName,
        'skills_lint-linux-x64.tar.gz',
        'skills_lint-macos-x64.tar.gz',
      ]);
    });

    test('throws when a file no longer matches its checksum', () {
      writeChecksum(write('skills_lint-linux-x64.tar.gz', 'abc'));
      write('skills_lint-linux-x64.tar.gz', 'changed');
      expect(
        () => mergeChecksums(dir),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            contains('skills_lint-linux-x64.tar.gz'),
          ),
        ),
      );
    });

    test('throws when an archive has no checksum', () {
      writeChecksum(write('skills_lint-linux-x64.tar.gz', 'abc'));
      write('skills_lint-macos-x64.tar.gz', 'def');
      expect(
        () => mergeChecksums(dir),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            contains('skills_lint-macos-x64.tar.gz'),
          ),
        ),
      );
    });

    test('throws when a checksum names a file that does not exist', () {
      write('skills_lint-linux-x64.tar.gz.sha256', '$_abcSha256  skills_lint-linux-x64.tar.gz\n');
      expect(() => mergeChecksums(dir), throwsA(isA<ReleaseException>()));
    });

    test('throws when there are no archives', () {
      expect(() => mergeChecksums(dir), throwsA(isA<ReleaseException>()));
    });
  });

  group('parseSha256Sums', () {
    final String first = 'a' * 64;
    final String second = 'b' * 64;

    test('reads "<sha256>  <name>" lines and skips blank lines', () {
      expect(parseSha256Sums('$first  skills_lint-macos-arm64.tar.gz\n\n$second  pubspec.lock\n'), {
        'skills_lint-macos-arm64.tar.gz': first,
        'pubspec.lock': second,
      });
    });

    test('rejects a line in another format', () {
      expect(
        () => parseSha256Sums('$first skills_lint-macos-arm64.tar.gz\n'),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            contains('$first skills_lint-macos-arm64.tar.gz'),
          ),
        ),
      );
    });
  });
}
