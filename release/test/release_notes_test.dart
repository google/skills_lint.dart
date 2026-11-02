// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
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
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            'CHANGELOG.md has no "## 0.7.0" heading.',
          ),
        ),
      );
    });

    test('returns an empty string when the section has no entries', () {
      expect(changelogSection('## 1.0.0\n\n## 0.9.0\n- Old.\n', '1.0.0'), isEmpty);
    });
  });

  group('releaseNotes', () {
    ReleaseInfo info(String version, ReleaseMode mode) => ReleaseInfo(
      version: version,
      tag: '$tagPrefix$version',
      prerelease: isPrerelease(version),
      mode: mode,
    );

    const emptyWip = '## 1.1.0-wip\n\n## 1.0.0\n\n- Released.\n';
    const emptyRelease = '## 1.1.0\n\n## 1.0.0\n\n- Released.\n';
    final Matcher throwsNoEntries = throwsA(
      isA<ReleaseException>().having(
        (e) => e.message,
        'message',
        'The "## 1.1.0" section of CHANGELOG.md has no entries.',
      ),
    );

    test("returns the version's section in every mode", () {
      for (final ReleaseMode mode in ReleaseMode.values) {
        expect(releaseNotes(_changelog, info('0.6.0', mode)), '- Released.\n  More detail.');
        expect(releaseNotes(_changelog, info('0.6.0-wip', mode)), '- Added a flag.');
      }
    });

    test('in a dry run, says that an empty -wip section has no entries yet', () {
      expect(
        releaseNotes(emptyWip, info('1.1.0-wip', ReleaseMode.dryRun)),
        'Dry run of 1.1.0-wip: the "## 1.1.0-wip" section of CHANGELOG.md has no entries yet.',
      );
    });

    test('in a dry run, accepts an empty section for the -wip version of a build', () {
      expect(
        releaseNotes(
          '## 1.0.0+1-wip\n\n## 1.0.0\n\n- Released.\n',
          info('1.0.0+1-wip', ReleaseMode.dryRun),
        ),
        'Dry run of 1.0.0+1-wip: the "## 1.0.0+1-wip" section of CHANGELOG.md has no entries yet.',
      );
    });

    test('throws for an empty section of a release version in a dry run', () {
      expect(() => releaseNotes(emptyRelease, info('1.1.0', ReleaseMode.dryRun)), throwsNoEntries);
    });

    test('throws for an empty section of a prerelease other than -wip in a dry run', () {
      expect(
        () => releaseNotes(
          '## 1.0.0-dev.1\n\n## 0.9.0\n\n- Old.\n',
          info('1.0.0-dev.1', ReleaseMode.dryRun),
        ),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            'The "## 1.0.0-dev.1" section of CHANGELOG.md has no entries.',
          ),
        ),
      );
    });

    test('throws for an empty section when staging a release', () {
      expect(() => releaseNotes(emptyRelease, info('1.1.0', ReleaseMode.stage)), throwsNoEntries);
    });

    test('throws when the version has no heading, even in a dry run', () {
      expect(
        () => releaseNotes(_changelog, info('0.7.0-wip', ReleaseMode.dryRun)),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            'CHANGELOG.md has no "## 0.7.0-wip" heading.',
          ),
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
