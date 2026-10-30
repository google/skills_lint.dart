// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/git_executable.dart';
import 'package:test/test.dart';

void main() {
  group('resolveGitExecutable', () {
    test('returns the bare name on macOS and Linux', () {
      expect(
        resolveGitExecutable(
          isWindows: false,
          environment: const {'PATH': '.:/usr/bin'},
          currentDirectory: '/repo',
          fileExists: (_) => true,
        ),
        'git',
      );
    });

    group('on Windows', () {
      String? resolve(String path, Set<String> existing, {String cwd = r'C:\repo'}) =>
          resolveGitExecutable(
            isWindows: true,
            environment: {'Path': path},
            currentDirectory: cwd,
            fileExists: existing.contains,
          );

      test('returns git.exe from the first PATH directory that has it', () {
        expect(
          resolve(r'C:\Windows;C:\Program Files\Git\cmd;C:\other', {
            r'C:\Program Files\Git\cmd\git.exe',
            r'C:\other\git.exe',
          }),
          r'C:\Program Files\Git\cmd\git.exe',
        );
      });

      test('never returns git.exe from the current directory', () {
        expect(resolve(r'C:\Program Files\Git\cmd', {r'C:\repo\git.exe'}), isNull);
      });

      test('skips PATH entries that name the current directory', () {
        expect(
          resolve(r'C:\repo;C:\Repo\;.;;C:\Git\cmd', {
            r'C:\repo\git.exe',
            r'C:\Repo\git.exe',
            r'C:\Git\cmd\git.exe',
          }),
          r'C:\Git\cmd\git.exe',
        );
      });

      test('skips relative PATH entries', () {
        expect(resolve(r'bin;C:\Git\cmd', {r'C:\repo\bin\git.exe', r'bin\git.exe'}), isNull);
      });

      test('reads PATH case-insensitively and strips quotes', () {
        expect(
          resolveGitExecutable(
            isWindows: true,
            environment: const {'PATH': r'"C:\Program Files\Git\cmd"'},
            currentDirectory: r'C:\repo',
            fileExists: {r'C:\Program Files\Git\cmd\git.exe'}.contains,
          ),
          r'C:\Program Files\Git\cmd\git.exe',
        );
      });

      test('returns null when PATH is unset', () {
        expect(
          resolveGitExecutable(
            isWindows: true,
            environment: const {},
            currentDirectory: r'C:\repo',
            fileExists: (_) => true,
          ),
          isNull,
        );
      });
    });
  });
}
