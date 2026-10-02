// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Works out which GitHub release a workflow run creates.
library;

import 'package:yaml/yaml.dart';

import 'release_exception.dart';

/// The prefix of the tags that release skills_lint. Pushing such a tag also
/// publishes the package to pub.dev.
const String tagPrefix = 'skills_lint-v';

/// The GitHub release that a workflow run creates.
///
/// A `dryRun` release stays a draft under a tag that no workflow publishes.
typedef ReleaseInfo = ({String version, String tag, bool prerelease, bool dryRun});

final RegExp _whitespace = RegExp(r'\s');
final RegExp _runId = RegExp(r'^\d+$');

/// Returns the `version` from the [pubspec] YAML text.
///
/// Throws a [ReleaseException] if there is no version, or if it holds
/// whitespace, which would let it add lines to `$GITHUB_ENV`.
String readPubspecVersion(String pubspec) {
  final Object? yaml = loadYaml(pubspec);
  final Object? version = yaml is YamlMap ? yaml['version'] : null;
  if (version is! String || version.isEmpty) {
    throw ReleaseException('pubspec.yaml has no version string.');
  }
  if (version.contains(_whitespace)) {
    throw ReleaseException('The pubspec.yaml version "$version" holds whitespace.');
  }
  return version;
}

/// Returns the release for a workflow run triggered by [event] on
/// [refName], for the package [version].
///
/// - A `push` of the tag `skills_lint-v<version>` releases that tag. Throws a
///   [ReleaseException] if [refName] is any other tag.
/// - A `workflow_dispatch` is a dry run, tagged `dry-run-<version>-<runId>`.
///   Throws a [ReleaseException] if [runId] is not a number.
/// - Throws a [ReleaseException] for any other event.
///
/// A version with a `-` suffix, such as `1.0.0-wip`, is a prerelease.
ReleaseInfo resolveRelease({
  required String version,
  required String event,
  required String refName,
  required String runId,
}) {
  final String tag;
  final bool dryRun;
  switch (event) {
    case 'push':
      tag = '$tagPrefix$version';
      if (refName != tag) {
        throw ReleaseException(
          'The tag $refName does not match the pubspec.yaml version $version. '
          'Push the tag $tag, or change the version.',
        );
      }
      dryRun = false;
    case 'workflow_dispatch':
      if (!_runId.hasMatch(runId)) {
        throw ReleaseException('The run ID "$runId" is not a number.');
      }
      tag = 'dry-run-$version-$runId';
      dryRun = true;
    default:
      throw ReleaseException(
        'A $event event does not create a release. Push a $tagPrefix tag, or run the '
        'workflow manually for a dry run.',
      );
  }
  return (version: version, tag: tag, prerelease: version.contains('-'), dryRun: dryRun);
}

/// Returns [info] as `NAME=value` lines for `$GITHUB_ENV`.
String environmentLines(ReleaseInfo info) =>
    'VERSION=${info.version}\n'
    'TAG=${info.tag}\n'
    'PRERELEASE=${info.prerelease}\n'
    'DRY_RUN=${info.dryRun}\n';
