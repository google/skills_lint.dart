// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/path_utils.dart';
import 'package:test/test.dart';

void main() {
  group('expandPath', () {
    test('expands tilde at start of path when HOME environment is available', () {
      final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      const rawPath = '~/some/path';

      final String result = expandPath(rawPath);

      if (home != null) {
        expect(result, equals(p.join(home, 'some/path')));
      } else {
        expect(result, equals(rawPath));
      }
    });

    test('does not expand tilde when present elsewhere in the path', () {
      const rawPath = 'some/~/path';

      final String result = expandPath(rawPath);

      expect(result, equals(rawPath));
    });

    test('returns standard relative and absolute paths unchanged', () {
      expect(expandPath('some/path'), equals('some/path'));
      expect(expandPath('/absolute/path'), equals('/absolute/path'));
    });
  });

  group('canonicalizePath boundary contract', () {
    test('anchors relative path to baseDirectory and normalizes', () {
      final String baseDir = p.normalize(p.absolute('some/base/dir'));
      const relativePath = 'skills/valid';

      final String result = canonicalizePath(relativePath, baseDirectory: baseDir);

      expect(result, equals(p.join(baseDir, 'skills', 'valid')));
    });

    test('collapses relative parent and current directory segments', () {
      final String baseDir = p.normalize(p.absolute('some/base/dir'));
      const relativePathWithDots = './skills/../skills/valid';

      final String result = canonicalizePath(relativePathWithDots, baseDirectory: baseDir);

      expect(result, equals(p.join(baseDir, 'skills', 'valid')));
    });

    test('preserves already absolute path without prepending baseDirectory', () {
      final String baseDir = p.normalize(p.absolute('some/base/dir'));
      final String absolutePath = p.normalize(p.absolute('other/root/path'));

      final String result = canonicalizePath(absolutePath, baseDirectory: baseDir);

      expect(result, equals(absolutePath));
    });

    test('expands tilde and normalizes without prepending baseDirectory', () {
      final String baseDir = p.normalize(p.absolute('some/base/dir'));
      final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

      if (home != null) {
        expect(
          canonicalizePath('~/my-skills', baseDirectory: baseDir),
          equals(p.normalize(p.join(home, 'my-skills'))),
        );
        expect(canonicalizePath('~', baseDirectory: baseDir), equals(p.normalize(home)));
      }
    });

    test('is idempotent when canonicalizing already canonical paths', () {
      final String baseDir1 = p.normalize(p.absolute('base/dir/one'));
      final String baseDir2 = p.normalize(p.absolute('base/dir/two'));
      const relativePath = 'nested/skill';

      final String firstPass = canonicalizePath(relativePath, baseDirectory: baseDir1);
      final String secondPass = canonicalizePath(firstPass, baseDirectory: baseDir2);

      expect(secondPass, equals(firstPass));
      expect(secondPass, equals(p.join(baseDir1, 'nested', 'skill')));
    });
  });

  group('normalizeSkillNameToken', () {
    test('converts underscores to hyphens', () {
      expect(normalizeSkillNameToken('skills_lint_setup'), 'skills-lint-setup');
      expect(normalizeSkillNameToken('my_custom_rule'), 'my-custom-rule');
    });

    test('preserves hyphens and lowercases', () {
      expect(normalizeSkillNameToken('skills-lint-setup'), 'skills-lint-setup');
      expect(normalizeSkillNameToken('My-Skill-Name'), 'my-skill-name');
    });

    test('preserves digits and alphanumeric sequences', () {
      expect(normalizeSkillNameToken('v2_api_3'), 'v2-api-3');
      expect(normalizeSkillNameToken('step42_test'), 'step42-test');
    });

    test('deduplicates consecutive hyphens and underscores', () {
      expect(normalizeSkillNameToken('skills___lint---setup'), 'skills-lint-setup');
      expect(normalizeSkillNameToken('foo-_-bar'), 'foo-bar');
    });

    test('strips leading and trailing hyphens and underscores', () {
      expect(normalizeSkillNameToken('---skills-lint---'), 'skills-lint');
      expect(normalizeSkillNameToken('___my_skill___'), 'my-skill');
      expect(normalizeSkillNameToken('-__foo-bar__-'), 'foo-bar');
    });

    test('replaces invalid characters with hyphens', () {
      expect(normalizeSkillNameToken('skill@name#1!'), 'skill-name-1');
      expect(normalizeSkillNameToken('foo.bar baz'), 'foo-bar-baz');
    });

    test('truncates to maxLength and strips trailing hyphen', () {
      final String longInput = 'a' * 70;
      final trailingHyphenInput = '${'a' * 63}-bbbb';

      final String normalized = normalizeSkillNameToken(longInput);
      final String truncated = normalizeSkillNameToken(trailingHyphenInput);

      expect(normalized.length, 64);
      expect(normalized, 'a' * 64);
      expect(truncated.length, 63);
      expect(truncated, 'a' * 63);
      expect(truncated.endsWith('-'), isFalse);
    });
  });
}
