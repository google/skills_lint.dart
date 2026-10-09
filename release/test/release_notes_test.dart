// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_notes.dart';
import 'package:test/test.dart';

const String _changelog = '''
## 0.6.0-wip

- Added a flag.

## 0.6.0

- Released.
  More detail.

## 0.5.0

- Older.
''';

void main() {
  group('changelogSection', () {
    test('returns the lines under the version heading, up to the next heading', () {
      expect(changelogSection(_changelog, '0.6.0'), '- Released.\n  More detail.');
    });

    test('matches the whole heading, not a heading that starts with the version', () {
      expect(changelogSection(_changelog, '0.6.0-wip'), '- Added a flag.');
    });

    test('returns the last section', () {
      expect(changelogSection(_changelog, '0.5.0'), '- Older.');
    });

    test('accepts Windows line endings', () {
      expect(changelogSection(_changelog.replaceAll('\n', '\r\n'), '0.5.0'), '- Older.');
    });

    test('throws when the version has no heading', () {
      expect(
        () => changelogSection(_changelog, '0.7.0'),
        throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains('## 0.7.0'))),
      );
    });

    test('throws when the section is empty', () {
      expect(
        () => changelogSection('## 1.0.0\n\n## 0.9.0\n- Old.\n', '1.0.0'),
        throwsA(
          isA<ReleaseException>().having((e) => e.message, 'message', contains('no entries')),
        ),
      );
    });
  });

  group('hasChangelogHeading', () {
    test('finds the heading that changelogSection reads', () {
      expect(hasChangelogHeading(_changelog, '0.6.0'), isTrue);
      expect(hasChangelogHeading(_changelog.replaceAll('\n', '\r\n'), '0.6.0'), isTrue);
    });

    test('ignores a version without a heading of its own', () {
      expect(hasChangelogHeading(_changelog, '0.6'), isFalse);
      expect(hasChangelogHeading('  ## 0.6.0\n', '0.6.0'), isFalse);
    });
  });
}
