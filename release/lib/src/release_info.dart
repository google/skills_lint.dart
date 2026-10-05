// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Works out what a run of the release workflow does.
library;

import 'package:yaml/yaml.dart';

import 'release_exception.dart';

/// The prefix of the tags that release skills_lint. pub.dev accepts
/// publishing only from a workflow run on a tag that matches
/// `skills_lint-v{{version}}`.
const String tagPrefix = 'skills_lint-v';

/// The branch that releases start from.
const String releaseBranch = 'main';

/// What a run of the release workflow does.
enum ReleaseMode {
  /// Tests the release scripts, builds and checks every asset, and creates
  /// nothing.
  dryRun,

  /// Does what [dryRun] does, then creates the tag and a draft GitHub release
  /// and starts the run that publishes them.
  stage,

  /// Publishes the package to pub.dev, then the draft GitHub release.
  publish,
}

/// The release that a workflow run works on.
typedef ReleaseInfo = ({String version, String tag, bool prerelease, ReleaseMode mode});

/// The characters a version may hold. A version is written to
/// `$GITHUB_OUTPUT` and into `install.sh`, so it may not hold whitespace,
/// quotes or shell syntax.
final RegExp _versionCharacters = RegExp(r'^[0-9A-Za-z.+-]+$');

/// Returns the `version` from the [pubspec] YAML text.
///
/// Throws a [ReleaseException] if there is no version, or if it holds a
/// character other than a letter, digit, `.`, `+` or `-`.
String readPubspecVersion(String pubspec) {
  final Object? yaml = loadYaml(pubspec);
  final Object? version = yaml is YamlMap ? yaml['version'] : null;
  if (version is! String || version.isEmpty) {
    throw ReleaseException('pubspec.yaml has no version string.');
  }
  if (!_versionCharacters.hasMatch(version)) {
    throw ReleaseException(
      'The pubspec.yaml version "$version" holds a character other than a letter, digit, '
      '".", "+" or "-".',
    );
  }
  return version;
}

/// Returns the release for a workflow run of [event] on the ref [refName] of
/// type [refType] (`branch` or `tag`), for the package [version]. [release]
/// is the `release` input of a `workflow_dispatch` run.
///
/// - A `pull_request` run, or a `workflow_dispatch` run on a branch without
///   [release], is a [ReleaseMode.dryRun].
/// - A `workflow_dispatch` run on [releaseBranch] with [release] is a
///   [ReleaseMode.stage].
/// - A `workflow_dispatch` run on the tag `skills_lint-v<version>` with
///   [release] is a [ReleaseMode.publish].
///
/// Throws a [ReleaseException] for any other run, and for a stage or publish
/// run of a `-wip` version. A version with any other `-` suffix, such as
/// `1.0.0-dev.1`, is a prerelease.
ReleaseInfo resolveRelease({
  required String version,
  required String event,
  required String refType,
  required String refName,
  required bool release,
}) {
  final tag = '$tagPrefix$version';
  final ReleaseMode mode = switch ((event, refType, release)) {
    ('pull_request', _, _) || ('workflow_dispatch', 'branch', false) => ReleaseMode.dryRun,
    ('workflow_dispatch', 'branch', true) => ReleaseMode.stage,
    ('workflow_dispatch', 'tag', true) => ReleaseMode.publish,
    ('workflow_dispatch', 'tag', false) => throw ReleaseException(
      'A run on the tag $refName publishes it, so it needs the release input.',
    ),
    _ => throw ReleaseException('The release workflow does not run for "$event" events.'),
  };
  if (mode == ReleaseMode.stage && refName != releaseBranch) {
    throw ReleaseException('Releases start from $releaseBranch, not $refName.');
  }
  if (mode == ReleaseMode.publish && refName != tag) {
    throw ReleaseException(
      'The tag $refName does not match the pubspec.yaml version $version; expected $tag.',
    );
  }
  if (mode != ReleaseMode.dryRun && version.contains('-wip')) {
    throw ReleaseException(
      '$version is a -wip version. Set the version to release in pubspec.yaml and '
      'CHANGELOG.md first.',
    );
  }
  return (version: version, tag: tag, prerelease: version.contains('-'), mode: mode);
}

/// Returns [info] as `name=value` lines for `$GITHUB_OUTPUT`.
String outputLines(ReleaseInfo info) =>
    'version=${info.version}\n'
    'tag=${info.tag}\n'
    'prerelease=${info.prerelease}\n'
    'mode=${info.mode.name}\n';
