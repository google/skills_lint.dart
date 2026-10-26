// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/readme_anchors.dart';

void main() {
  group('slugify', () {
    test('drops the period after a number', () {
      expect(slugify('3. Custom Rules'), '3-custom-rules');
    });

    test('drops backticks and dots inside code spans', () {
      expect(slugify('2. `install.sh` — Linux + macOS'), '2-installsh--linux--macos');
    });

    test('keeps hyphens and underscores', () {
      expect(slugify('Dart-native pre_commit'), 'dart-native-pre_commit');
    });

    test('drops non-ASCII letters, as pub.dev does', () {
      expect(slugify('Café é'), 'caf-');
    });

    test('drops tabs inside a heading, as pub.dev does', () {
      expect(slugify('a\tb'), 'ab');
    });

    test('drops a trailing colon', () {
      expect(slugify('Recipe: GitHub Actions'), 'recipe-github-actions');
    });
  });

  group('headingAnchors', () {
    test('matches the ids pub.dev renders for README headings', () {
      // Expected ids copied from https://pub.dev/packages/skills_lint.
      const markdown =
          '### 1. Dart developers — pub.dev\n'
          '#### As a project dev_dependency\n'
          '### 2. `install.sh` — Linux + macOS, no Dart required\n'
          '### Recipe: Dart-native pre-commit hook\n';
      expect(headingAnchors(markdown), [
        '1-dart-developers--pubdev',
        'as-a-project-dev_dependency',
        '2-installsh--linux--macos-no-dart-required',
        'recipe-dart-native-pre-commit-hook',
      ]);
    });

    test('numbers repeated headings with -2, -3, as pub.dev does', () {
      expect(headingAnchors('## Usage\n### Flags\n## Flags\n# flags\n'), [
        'usage',
        'flags',
        'flags-2',
        'flags-3',
      ]);
    });

    test('a ```` fence is not closed by a shorter ``` line', () {
      expect(headingAnchors('````\n```\n# hidden\n````\n# shown\n'), ['shown']);
    });

    test('skips # lines inside fenced code blocks', () {
      const markdown = '## Before\n```yaml\n# comment\n```\n~~~\n# also\n~~~\n## After\n';
      expect(headingAnchors(markdown), ['before', 'after']);
    });

    test('a ~~~ line does not close a ``` fence', () {
      expect(headingAnchors('```\n~~~\n# hidden\n```\n# shown\n'), ['shown']);
    });

    test('ignores lines that are not headings', () {
      expect(headingAnchors('#nospace\n####### seven\n    # indented code\ntext\n'), isEmpty);
    });

    test('drops closing hashes', () {
      expect(headingAnchors('## Built-in Rules ##\n'), ['built-in-rules']);
    });
  });
}
