// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Works out what a run of the build workflow,
/// `.github/workflows/release_build_and_tag.yaml`, does.
library;

import 'package:yaml/yaml.dart';

import 'release_exception.dart';

/// The prefix of the tags that release skills_lint. pub.dev accepts
/// publishing only from a workflow run on a tag that matches
/// `skills_lint-v{{version}}`.
const String tagPrefix = 'skills_lint-v';

/// The branch that releases start from.
const String releaseBranch = 'main';

/// What a run of the build workflow does.
enum ReleaseMode {
  /// Tests the release scripts, builds and checks every asset, and creates
  /// nothing.
  dryRun,

  /// Does what [dryRun] does, then creates the tag and a draft GitHub release
  /// and starts the workflow that publishes them.
  stage,
}

/// The release that a run of the build workflow works on.
final class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.prerelease,
    required this.mode,
  });

  /// The version in the skills_lint `pubspec.yaml`.
  final String version;

  /// The tag that releases [version]: [tagPrefix] followed by [version].
  final String tag;

  /// Whether [version] has a `-` suffix, such as `1.0.0-dev.1`. GitHub
  /// doesn't offer a prerelease as the latest release.
  final bool prerelease;

  /// What this run does: a dry run, or staging the tag and draft release.
  final ReleaseMode mode;
}

/// The characters a version may hold. A version is written to
/// `$GITHUB_OUTPUT` and into `install.sh`, so it may not hold whitespace,
/// quotes or shell syntax.
final RegExp _versionCharacters = RegExp(r'^[0-9A-Za-z.+-]+$');

/// `<major>.<minor>.<patch>` with an optional numeric build, such as `0.5.4`
/// or `0.5.4+1`.
final RegExp _homebrewVersion = RegExp(r'^\d+\.\d+\.\d+(\+\d+)?$');

/// Whether the Homebrew formula can install [version]: a release version,
/// such as `0.5.4` or `0.5.4+1`, whose build, if it has one, is a number.
///
/// Homebrew installs the formula for every user, so it never names a
/// prerelease, and the formula's livecheck regex reads only numeric builds.
bool isHomebrewVersion(String version) => _homebrewVersion.hasMatch(version);

/// The release that [pubspecVersion] works toward: [pubspecVersion] without
/// `-wip`.
String pendingRelease(String pubspecVersion) => pubspecVersion.replaceFirst('-wip', '');

/// The version that the Homebrew formula names for a run of [version], or
/// null for a prerelease, which the formula skips.
///
/// A dry run of a `-wip` version gives the release it works toward, so the
/// run can check that the formula template renders it.
String? formulaVersion(String version) {
  final String pending = pendingRelease(version);
  return isHomebrewVersion(pending) ? pending : null;
}

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

/// Returns the release for a run of the build workflow for [event] on the
/// ref [refName] of type [refType] (`branch` or `tag`), for the package
/// [version]. [releaseVersion] is the run's `version` input: the version to
/// release, or empty.
///
/// - A `pull_request` run, or a `workflow_dispatch` run without a
///   [releaseVersion], is a [ReleaseMode.dryRun].
/// - A `workflow_dispatch` run on [releaseBranch] with a [releaseVersion]
///   that is [version] is a [ReleaseMode.stage].
///
/// Throws a [ReleaseException] for any other run, for a stage run of a `-wip`
/// version, and for a stage run of a release whose build is not numeric, such
/// as `0.5.4+hotfix`. A version with any other `-` suffix, such as
/// `1.0.0-dev.1`, is a prerelease.
ReleaseInfo resolveRelease({
  required String version,
  required String event,
  required String refType,
  required String refName,
  required String releaseVersion,
}) {
  final ReleaseMode mode = switch (event) {
    'pull_request' => ReleaseMode.dryRun,
    'workflow_dispatch' => releaseVersion.isEmpty ? ReleaseMode.dryRun : ReleaseMode.stage,
    _ => throw ReleaseException('The build workflow does not run for "$event" events.'),
  };
  if (mode == ReleaseMode.stage) {
    _checkStage(
      version: version,
      refType: refType,
      refName: refName,
      releaseVersion: releaseVersion,
    );
  }
  return ReleaseInfo(
    version: version,
    tag: '$tagPrefix$version',
    prerelease: version.contains('-'),
    mode: mode,
  );
}

/// Throws a [ReleaseException] unless a run on [refName] of type [refType]
/// can release [version] when asked for [releaseVersion].
void _checkStage({
  required String version,
  required String refType,
  required String refName,
  required String releaseVersion,
}) {
  if (refType != 'branch' || refName != releaseBranch) {
    throw ReleaseException(
      'Releases start from $releaseBranch, not $refName. Run the workflow on $releaseBranch.',
    );
  }
  if (releaseVersion != version) {
    throw ReleaseException(
      'The version input is $releaseVersion, but pubspec.yaml has $version. Run the workflow with '
      'version $version, or first merge a pull request that sets the version to release.',
    );
  }
  if (version.contains('-wip')) {
    throw ReleaseException(
      '$version is a -wip version. Set the version to release in pubspec.yaml and '
      'CHANGELOG.md first.',
    );
  }
  if (!version.contains('-') && !isHomebrewVersion(version)) {
    throw ReleaseException(
      'The Homebrew formula cannot name $version: it takes <major>.<minor>.<patch> with an '
      'optional numeric build, such as 0.5.4+1.',
    );
  }
}

/// Returns [info] as `name=value` lines for `$GITHUB_OUTPUT`.
String outputLines(ReleaseInfo info) =>
    'version=${info.version}\n'
    'tag=${info.tag}\n'
    'prerelease=${info.prerelease}\n'
    'mode=${info.mode.name}\n'
    'formula-version=${formulaVersion(info.version) ?? ''}\n';
