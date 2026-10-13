// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:skills_lint_release/src/merged_pull_request.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:test/test.dart';

const String _sha = '3d3c42e5aac5ba805825da76410c181273ba90b1';

/// One pull request as GitHub's API returns it, with only the fields that
/// [checkMergedPullRequest] reads.
Map<String, Object?> _pull({required String? mergedAt, required String base}) => {
  'merged_at': mergedAt,
  'base': {'ref': base},
};

const String _mergedAt = '2026-10-12T15:21:55Z';

/// Checks that a release starts only from a commit that a pull request merged
/// into the release branch, from the GitHub API's answer for the commit.
void main() {
  test('accepts a commit that a pull request merged into main', () {
    final String pulls = jsonEncode([
      _pull(mergedAt: null, base: releaseBranch),
      _pull(mergedAt: _mergedAt, base: releaseBranch),
    ]);
    expect(() => checkMergedPullRequest(pulls, sha: _sha), returnsNormally);
  });

  test('rejects a commit with no merged pull request into main, and names it', () {
    final Map<String, String> pullsByCase = {
      'no pull request': jsonEncode([]),
      'an open pull request': jsonEncode([_pull(mergedAt: null, base: releaseBranch)]),
      'a pull request merged into another branch': jsonEncode([
        _pull(mergedAt: _mergedAt, base: 'feature'),
      ]),
    };
    for (final MapEntry(key: String reason, value: String pulls) in pullsByCase.entries) {
      expect(
        () => checkMergedPullRequest(pulls, sha: _sha),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            allOf(contains(_sha), contains('merged into $releaseBranch')),
          ),
        ),
        reason: reason,
      );
    }
  });

  test('rejects an answer that is not a list of pull requests', () {
    expect(
      () => checkMergedPullRequest('{"message": "Not Found"}', sha: _sha),
      throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains('Not Found'))),
    );
  });
}
