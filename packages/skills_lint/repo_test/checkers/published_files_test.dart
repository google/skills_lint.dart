// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/published_files.dart';

void main() {
  group('parsePublishedFiles', () {
    test('returns nested file paths and skips directories', () {
      const output = '''
Publishing skills_lint 0.5.3-wip to https://pub.dev:
├── CHANGELOG.md (5 KB)
├── lib
│   └── src
│       └── a.dart (<1 KB)
├── skills
│   ├── one
│   │   └── SKILL.md (2 KB)
│   └── two
│       └── SKILL.md (3 KB)
└── pubspec.yaml (1 KB)

Total compressed archive size: 151 KB.
''';
      expect(parsePublishedFiles(output), {
        'CHANGELOG.md',
        'lib/src/a.dart',
        'skills/one/SKILL.md',
        'skills/two/SKILL.md',
        'pubspec.yaml',
      });
    });

    test('accepts Windows line endings', () {
      expect(parsePublishedFiles('├── lib\r\n│   └── a.dart (1 KB)\r\n'), {'lib/a.dart'});
    });

    test('returns nothing for output without a tree', () {
      expect(parsePublishedFiles('Package has 0 warnings.\n'), isEmpty);
    });
  });
}
