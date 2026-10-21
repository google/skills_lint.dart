// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:skills_lint_release/src/pub_dev_environment.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:test/test.dart';

/// GitHub's JSON for an environment with protection rules of [ruleTypes].
String _environment({required List<String> ruleTypes}) => jsonEncode({
  'name': pubDevEnvironment,
  'protection_rules': [
    for (final type in ruleTypes) {'id': 1, 'type': type},
  ],
});

/// GitHub's JSON for deployment branch policies, each a `(type, name)` pair.
String _policies(List<(String, String)> policies) => jsonEncode({
  'total_count': policies.length,
  'branch_policies': [
    for (final (type, name) in policies) {'id': 1, 'type': type, 'name': name},
  ],
});

final String _releaseTags = _policies([('tag', '$tagPrefix*')]);

Matcher _throwsNaming(String part) =>
    throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains(part)));

void main() {
  test('passes with a required reviewer and only the release tag rule', () {
    expect(
      () => checkPubDevEnvironment(
        environment: _environment(ruleTypes: ['wait_timer', 'required_reviewers', 'branch_policy']),
        branchPolicies: _releaseTags,
      ),
      returnsNormally,
    );
  });

  test('fails without a required reviewer, and names the rules it found', () {
    expect(
      () => checkPubDevEnvironment(
        environment: _environment(ruleTypes: ['branch_policy']),
        branchPolicies: _releaseTags,
      ),
      _throwsNaming('rules: branch_policy;'),
    );
  });

  test('fails unless the release tag rule is the only rule, and names the rules it found', () {
    for (final policies in [
      <(String, String)>[],
      [('branch', 'main')],
      [('tag', '*')],
      [('tag', '$tagPrefix*'), ('branch', 'main')],
    ]) {
      expect(
        () => checkPubDevEnvironment(
          environment: _environment(ruleTypes: ['required_reviewers']),
          branchPolicies: _policies(policies),
        ),
        _throwsNaming(
          'policies: ${[for (final (type, name) in policies) '$type:$name'].join(' ')})',
        ),
        reason: '$policies',
      );
    }
  });

  test('fails on JSON that is not an environment, such as an error answer', () {
    expect(
      () => checkPubDevEnvironment(
        environment: '{"message": "Not Found"}',
        branchPolicies: '{"message": "Not Found"}',
      ),
      _throwsNaming('needs a required reviewer'),
    );
  });
}
