// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:test/test.dart';

Matcher _throwsReleaseException(String messagePart) =>
    throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains(messagePart)));

/// Calls [resolveRelease] for a `workflow_dispatch` run unless [event] says
/// otherwise.
ReleaseInfo _resolve({
  String version = '0.6.0',
  String event = 'workflow_dispatch',
  String refType = 'branch',
  String refName = 'main',
  bool release = false,
}) => resolveRelease(
  version: version,
  event: event,
  refType: refType,
  refName: refName,
  release: release,
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

    test('a run on a branch without release is a dry run, even for a -wip version', () {
      expect(_resolve(version: '0.6.0-wip').mode, ReleaseMode.dryRun);
      expect(_resolve(refName: 'feature').mode, ReleaseMode.dryRun);
    });

    test('a release run on main stages the tag for the version', () {
      final ReleaseInfo info = _resolve(release: true);
      expect(info.mode, ReleaseMode.stage);
      expect(info.tag, '${tagPrefix}0.6.0');
      expect(info.prerelease, isFalse);
    });

    test('a release run on another branch fails', () {
      expect(() => _resolve(release: true, refName: 'feature'), _throwsReleaseException('feature'));
    });

    test('a release run on the tag of the version publishes it', () {
      final ReleaseInfo info = _resolve(
        release: true,
        refType: 'tag',
        refName: '${tagPrefix}0.6.0',
      );
      expect(info.mode, ReleaseMode.publish);
      expect(info.tag, '${tagPrefix}0.6.0');
    });

    test('a release run on another tag fails', () {
      expect(
        () => _resolve(release: true, refType: 'tag', refName: '${tagPrefix}0.6.1'),
        _throwsReleaseException('${tagPrefix}0.6.1'),
      );
    });

    test('a run on a tag without release fails, so it cannot publish by accident', () {
      expect(
        () => _resolve(refType: 'tag', refName: '${tagPrefix}0.6.0'),
        throwsA(isA<ReleaseException>()),
      );
    });

    test('a -wip version is never staged or published', () {
      expect(() => _resolve(version: '0.6.0-wip', release: true), _throwsReleaseException('-wip'));
      expect(
        () => _resolve(
          version: '0.6.0-wip',
          release: true,
          refType: 'tag',
          refName: '${tagPrefix}0.6.0-wip',
        ),
        _throwsReleaseException('-wip'),
      );
    });

    test('a version with a suffix other than -wip is a prerelease', () {
      final ReleaseInfo info = _resolve(version: '0.6.0-dev.1', release: true);
      expect(info.mode, ReleaseMode.stage);
      expect(info.prerelease, isTrue);
    });

    test('a release with a numeric build is staged, and one with another build is not', () {
      final ReleaseInfo info = _resolve(version: '0.6.0+1', release: true);
      expect(info.mode, ReleaseMode.stage);
      expect(info.prerelease, isFalse);
      expect(
        () => _resolve(version: '0.6.0+hotfix', release: true),
        _throwsReleaseException('not a number'),
      );
      expect(_resolve(version: '0.6.0+hotfix').mode, ReleaseMode.dryRun);
    });

    test('other events fail', () {
      expect(() => _resolve(event: 'push'), _throwsReleaseException('push'));
    });
  });
}
