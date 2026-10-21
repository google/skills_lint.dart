// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks that the repository's pub.dev environment still guards publishing.
library;

import 'dart:convert';

import 'release_exception.dart';
import 'release_info.dart';

/// The GitHub Actions environment that pub.dev requires for publishing.
const String pubDevEnvironment = 'pub.dev';

/// Checks that the [pubDevEnvironment] environment protects publishing.
///
/// Throws a [ReleaseException] unless the environment has a required
/// reviewer and allows deployments only from [tagPrefix] tags.
///
/// The [environment] is the JSON that GitHub's
/// [get an environment](https://docs.github.com/en/rest/deployments/environments#get-an-environment)
/// API returns, and [branchPolicies] the JSON of its
/// [list deployment branch policies](https://docs.github.com/en/rest/deployments/branch-policies#list-deployment-branch-policies)
/// API.
// pub.dev checks only the environment's name, and GitHub re-creates a
// deleted environment with no protection when a job uses it. So the release
// stops before the tag unless the protection is in place.
void checkPubDevEnvironment({required String environment, required String branchPolicies}) {
  final List<String> rules = [];
  if (jsonDecode(environment) case {'protection_rules': final List<Object?> protectionRules}) {
    for (final rule in protectionRules) {
      if (rule case {'type': final String type}) {
        rules.add(type);
      }
    }
  }
  final List<String> policies = [];
  if (jsonDecode(branchPolicies) case {'branch_policies': final List<Object?> branchPolicyList}) {
    for (final policy in branchPolicyList) {
      if (policy case {'type': final String type, 'name': final String name}) {
        policies.add('$type:$name');
      }
    }
  }
  final bool hasReviewer = rules.contains('required_reviewers');
  final bool onlyReleaseTags = policies.length == 1 && policies[0] == 'tag:$tagPrefix*';
  if (!hasReviewer || !onlyReleaseTags) {
    throw ReleaseException(
      'The $pubDevEnvironment environment needs a required reviewer and only the $tagPrefix* tag '
      'rule (rules: ${rules.join(' ')}; policies: ${policies.join(' ')}). An admin must fix it in '
      'Settings > Environments, then re-run this job.',
    );
  }
}
