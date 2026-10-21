// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:test/test.dart';

Matcher _throwsReleaseException(String messagePart) =>
    throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains(messagePart)));

/// Calls [resolveRelease] for a `workflow_dispatch` run on main unless the
/// arguments say otherwise.
ReleaseInfo _resolve({
  String version = '0.6.0',
  String event = 'workflow_dispatch',
  String refType = 'branch',
  String refName = 'main',
  String? releaseVersion,
}) => resolveRelease(
  version: version,
  event: event,
  refType: refType,
  refName: refName,
  releaseVersion: releaseVersion,
);

void main() {
  group('readPubspecVersion', () {
    test('returns the version', () {
      expect(readPubspecVersion('name: skills_lint\nversion: 0.5.3-wip\n'), '0.5.3-wip');
    });

    test('throws without a version', () {
      expect(() => readPubspecVersion('name: skills_lint\n'), _throwsReleaseException('version'));
    });

    test('throws on a version that could add lines to GITHUB_OUTPUT or run in a shell', () {
      for (final yamlVersion in [r'"1.0.0\nX=y"', r"'1.0.0$(id)'", "'1.0.0\"'"]) {
        expect(
          () => readPubspecVersion('version: $yamlVersion\n'),
          _throwsReleaseException('1.0.0'),
          reason: yamlVersion,
        );
      }
    });
  });

  group('resolveRelease', () {
    test('a pull request is a dry run', () {
      expect(_resolve(event: 'pull_request', refName: '85/merge').mode, ReleaseMode.dryRun);
    });

    test('a run without a version to release is a dry run, even for a -wip version', () {
      expect(_resolve(version: '0.6.0-wip').mode, ReleaseMode.dryRun);
      expect(_resolve(refName: 'feature').mode, ReleaseMode.dryRun);
      expect(_resolve(refType: 'tag', refName: '${tagPrefix}0.6.0').mode, ReleaseMode.dryRun);
    });

    test('a run on main with the pubspec version stages the tag for it', () {
      final ReleaseInfo info = _resolve(releaseVersion: '0.6.0');
      expect(info.mode, ReleaseMode.stage);
      expect(info.tag, '${tagPrefix}0.6.0');
      expect(info.prerelease, isFalse);
    });

    test('a release from another branch, or from a tag named main, fails', () {
      expect(
        () => _resolve(releaseVersion: '0.6.0', refName: 'feature'),
        _throwsReleaseException('feature'),
      );
      expect(
        () => _resolve(releaseVersion: '0.6.0', refType: 'tag'),
        _throwsReleaseException('Releases start from main'),
      );
    });

    test('a version to release that is not the pubspec version fails and names both', () {
      expect(
        () => _resolve(releaseVersion: '0.6.1'),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            allOf(contains('0.6.1'), contains('0.6.0')),
          ),
        ),
      );
    });

    test('releasing before the version bump merges says to set the version first', () {
      expect(
        () => _resolve(version: '0.6.0-wip', releaseVersion: '0.6.0'),
        _throwsReleaseException('Set the version to release in pubspec.yaml'),
      );
    });

    test('a -wip version is never staged', () {
      expect(
        () => _resolve(version: '0.6.0-wip', releaseVersion: '0.6.0-wip'),
        _throwsReleaseException('-wip'),
      );
    });

    test('a version with a suffix other than -wip is a prerelease', () {
      final ReleaseInfo info = _resolve(version: '0.6.0-dev.1', releaseVersion: '0.6.0-dev.1');
      expect(info.mode, ReleaseMode.stage);
      expect(info.prerelease, isTrue);
    });

    test('a release with a numeric build is staged, and one with another build is not', () {
      final ReleaseInfo info = _resolve(version: '0.6.0+1', releaseVersion: '0.6.0+1');
      expect(info.mode, ReleaseMode.stage);
      expect(info.prerelease, isFalse);
      expect(
        () => _resolve(version: '0.6.0+hotfix', releaseVersion: '0.6.0+hotfix'),
        _throwsReleaseException('0.6.0+hotfix'),
      );
      expect(_resolve(version: '0.6.0+hotfix').mode, ReleaseMode.dryRun);
    });

    test('other events fail', () {
      expect(() => _resolve(event: 'push'), _throwsReleaseException('push'));
    });
  });

  group('outputLines', () {
    test('names the formula version that the Homebrew steps use, or none', () {
      expect(
        outputLines(_resolve(version: '0.6.0+1', releaseVersion: '0.6.0+1')),
        contains('formula-version=0.6.0+1\n'),
      );
      expect(outputLines(_resolve(version: '0.6.0-wip')), contains('formula-version=0.6.0\n'));
      expect(
        outputLines(_resolve(version: '1.0.0-dev.1', releaseVersion: '1.0.0-dev.1')),
        contains('formula-version=\n'),
      );
      expect(outputLines(_resolve(version: '0.6.0+hotfix')), contains('formula-version=\n'));
    });
  });
}
