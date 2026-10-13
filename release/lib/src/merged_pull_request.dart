// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks that a pull request merged a commit into the release branch.
library;

import 'dart:convert';

import 'release_exception.dart';
import 'release_info.dart';

// The keys of a pull request in GitHub's REST API that checkMergedPullRequest
// reads.
const String _mergedAtKey = 'merged_at';
const String _baseKey = 'base';
const String _refKey = 'ref';

/// Throws a [ReleaseException] unless [pulls] lists a pull request that
/// merged [sha] into [releaseBranch].
///
/// [pulls] is the JSON that GitHub's
/// [list pull requests associated with a commit](https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit)
/// API returns for [sha].
void checkMergedPullRequest(String pulls, {required String sha}) {
  final Object? decoded = jsonDecode(pulls);
  if (decoded is! List<Object?>) {
    throw ReleaseException('The pull requests of $sha are not a JSON list: $pulls');
  }
  for (final Object? pull in decoded) {
    if (_mergedInto(pull, releaseBranch)) {
      return;
    }
  }
  throw ReleaseException(
    'No merged pull request into $releaseBranch holds $sha. Release only commits that a pull '
    'request merged into $releaseBranch.',
  );
}

/// Whether [pull], one pull request from the API, merged into [branch].
bool _mergedInto(Object? pull, String branch) {
  if (pull is! Map<String, Object?> || pull[_mergedAtKey] == null) {
    return false;
  }
  final Object? base = pull[_baseKey];
  return base is Map<String, Object?> && base[_refKey] == branch;
}
