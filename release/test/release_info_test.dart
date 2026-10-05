// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:test/test.dart';

Matcher _throwsReleaseException(String messagePart) =>
    throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains(messagePart)));

void main() {
  group('readPubspecVersion', () {
    test('returns the version', () {
      expect(readPubspecVersion('name: skills_lint\nversion: 0.5.3-wip\n'), '0.5.3-wip');
    });

    test('throws without a version', () {
      expect(() => readPubspecVersion('name: skills_lint\n'), _throwsReleaseException('version'));
    });

    test('throws on a version with whitespace, which would break GITHUB_ENV', () {
      expect(
        () => readPubspecVersion('version: "1.0.0\\nX=y"\n'),
        _throwsReleaseException('1.0.0'),
      );
    });
  });

  group('resolveRelease', () {
    test('a tag push releases the tag when it matches the version', () {
      final ReleaseInfo info = resolveRelease(
        version: '0.6.0',
        event: 'push',
        refName: 'skills_lint-v0.6.0',
        runId: '123',
      );
      expect(info.version, '0.6.0');
      expect(info.tag, 'skills_lint-v0.6.0');
      expect(info.prerelease, isFalse);
      expect(info.dryRun, isFalse);
    });

    test('a tag push fails when the tag does not match the version', () {
      expect(
        () => resolveRelease(
          version: '0.6.0',
          event: 'push',
          refName: 'skills_lint-v0.6.1',
          runId: '123',
        ),
        _throwsReleaseException('skills_lint-v0.6.1'),
      );
    });

    test('a manual run is a dry run under a tag that no workflow publishes', () {
      final ReleaseInfo info = resolveRelease(
        version: '0.6.0-wip',
        event: 'workflow_dispatch',
        refName: 'main',
        runId: '456',
      );
      expect(info.tag, 'dry-run-0.6.0-wip-456');
      expect(info.tag, isNot(startsWith(tagPrefix)));
      expect(info.prerelease, isTrue);
      expect(info.dryRun, isTrue);
    });

    test('a manual run fails with a run ID that is not a number', () {
      expect(
        () => resolveRelease(
          version: '0.6.0',
          event: 'workflow_dispatch',
          refName: 'main',
          runId: '1\nX=y',
        ),
        _throwsReleaseException('run ID'),
      );
    });

    test('other events fail', () {
      expect(
        () => resolveRelease(version: '0.6.0', event: 'pull_request', refName: 'main', runId: '1'),
        _throwsReleaseException('pull_request'),
      );
    });
  });
}
