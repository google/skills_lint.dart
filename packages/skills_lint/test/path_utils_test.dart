// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/path_utils.dart';
import 'package:test/test.dart';

void main() {
  group('expandPath', () {
    test('expands tilde at start of path', () {
      final String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        expect(expandPath('~/some/path'), equals(p.join(home, 'some/path')));
      } else {
        // If home is null, it should return the path as is.
        expect(expandPath('~/some/path'), equals('~/some/path'));
      }
    });

    test('does not expand tilde not at start of path', () {
      expect(expandPath('some/~/path'), equals('some/~/path'));
    });

    test('returns path as is if it does not start with tilde', () {
      expect(expandPath('some/path'), equals('some/path'));
      expect(expandPath('/absolute/path'), equals('/absolute/path'));
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
      final String normalized = normalizeSkillNameToken(longInput);
      expect(normalized.length, 64);
      expect(normalized, 'a' * 64);

      // Truncation landing on a hyphen
      final trailingHyphenInput = '${'a' * 63}-bbbb';
      final String truncated = normalizeSkillNameToken(trailingHyphenInput);
      expect(truncated.length, 63);
      expect(truncated, 'a' * 63);
      expect(truncated.endsWith('-'), isFalse);
    });
  });
}
