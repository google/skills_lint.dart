// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks that a draft GitHub release holds exactly what the build of its
/// commit made, before the publish workflow publishes anything.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive.dart';
import 'checksums.dart';
import 'homebrew_formula.dart';
import 'line_endings.dart';
import 'paths.dart';
import 'release_exception.dart';
import 'release_info.dart';

/// The workflow that builds, attests and stages every release.
const String buildWorkflowPath = '.github/workflows/release_build_and_tag.yaml';

/// The release asset that installs the executable, `scripts/install.sh`
/// with the release's version.
const String installScriptAsset = 'install.sh';

/// The release asset that holds the dependencies the release was built
/// with.
const String lockfileAsset = 'pubspec.lock';

/// The release asset that holds the Homebrew formula for the release.
final String formulaAsset = p.basename(homebrewFormulaPath);

/// Runs [executable] with [arguments]. [verifyDraft] takes one so that tests
/// can stand in for `gh`.
typedef RunProcess = Future<ProcessResult> Function(String executable, List<String> arguments);

/// A draft release that matches the build of its commit.
final class VerifiedDraft {
  const VerifiedDraft({required this.version, required this.homebrew, required this.buildRuns});

  /// The version that the release's tag names.
  final String version;

  /// Whether the release has a Homebrew formula: every release that isn't a
  /// prerelease does.
  final bool homebrew;

  /// The URL of each build workflow run that attested the assets, sorted.
  final List<String> buildRuns;

  /// [version] and [homebrew] as `name=value` lines for `$GITHUB_OUTPUT`.
  String get outputLines => 'version=$version\nhomebrew=$homebrew\n';

  /// Markdown for the job summary, for the person who approves publishing to
  /// pub.dev.
  String get summary => [
    '### Before you approve the pub.dev job, check:',
    '- Version: $version',
    for (final String run in buildRuns) '- Build run: $run',
    '',
  ].join('\n');
}

/// Checks the draft release of [tag] and returns what the publish workflow
/// needs to know about it.
///
/// [refType] and [tag] are the type and name of the workflow run's ref, and
/// [pubspecVersion] is the version in the skills_lint `pubspec.yaml` at
/// [commit], which `dart pub publish` uploads. [releaseJson] is what
/// `gh release view <tag> --json isDraft,isPrerelease` printed, and [assets]
/// holds every asset of the draft. The draft must hold, for this commit's
/// build in [repository]:
///
/// - each [releaseTargets] archive, `SHA256SUMS`, `install.sh` and
///   `pubspec.lock`, plus `skills_lint.rb` unless it is a prerelease, and no
///   other file;
/// - files that match their checksums in `SHA256SUMS`;
/// - a `skills_lint.rb` that installs the tag's version;
/// - files that each have an attestation from a run of [buildWorkflowPath]
///   on [releaseBranch] at [commit], which `gh attestation verify` checks.
///
/// Throws a [ReleaseException] that says what to do if any of these fail,
/// or if the tag's version isn't [pubspecVersion].
Future<VerifiedDraft> verifyDraft({
  required String refType,
  required String tag,
  required String pubspecVersion,
  required String repository,
  required String commit,
  required String releaseJson,
  required Directory assets,
  RunProcess runProcess = Process.run,
}) async {
  final String version = _versionOfTag(refType: refType, tag: tag);
  if (version != pubspecVersion) {
    throw ReleaseException(
      '$tag names $version, but packages/skills_lint/pubspec.yaml at $commit has '
      '$pubspecVersion, so pub.dev would get the wrong version. Publish nothing from this tag: '
      'delete its draft, and release the next version with Build and tag a release.',
    );
  }
  final bool prerelease = isPrerelease(version);
  _checkDraft(releaseJson, tag: tag, prerelease: prerelease);

  final List<String> problems = [
    ..._fileProblems(assets, homebrew: !prerelease),
    if (!prerelease) ?_formulaProblem(assets, version: version),
  ];
  final Set<String> buildRuns = {};
  for (final File file in _files(assets)) {
    final ProcessResult result = await runProcess('gh', [
      'attestation',
      'verify',
      file.path,
      '--repo',
      repository,
      '--signer-workflow',
      '$repository/$buildWorkflowPath',
      '--source-ref',
      'refs/heads/$releaseBranch',
      '--source-digest',
      commit,
      '--format',
      'json',
    ]);
    final String name = p.basename(file.path);
    if (result.exitCode != 0) {
      problems.add('$name has no attestation from the build of $commit: ${result.stderr}'.trim());
      continue;
    }
    final List<String>? runs = _buildRuns('${result.stdout}');
    if (runs == null) {
      problems.add("gh attestation verify printed JSON for $name that this command can't read.");
      continue;
    }
    buildRuns.addAll(runs);
  }

  if (problems.isNotEmpty) {
    throw ReleaseException(
      "The draft of $tag doesn't match the build of $commit:\n"
      '${problems.map((problem) => '- $problem').join('\n')}\n'
      'Re-run this job once. If it fails again, delete the draft, then re-run the Stage job of '
      'the build.',
    );
  }
  return VerifiedDraft(
    version: version,
    homebrew: !prerelease,
    buildRuns: buildRuns.toList()..sort(),
  );
}

/// The version that [tag] releases.
///
/// Throws a [ReleaseException] unless the run is on a tag that starts with
/// [tagPrefix] and names a version.
String _versionOfTag({required String refType, required String tag}) {
  if (refType != 'tag' || !tag.startsWith(tagPrefix) || tag == tagPrefix) {
    throw ReleaseException(
      'Run this workflow on a $tagPrefix<version> tag, not $tag. Build and tag a release starts '
      'it.',
    );
  }
  final String version = tag.substring(tagPrefix.length);
  checkVersionCharacters(version, source: 'The version of $tag');
  return version;
}

/// Throws a [ReleaseException] unless [releaseJson] describes a draft whose
/// prerelease setting is [prerelease].
void _checkDraft(String releaseJson, {required String tag, required bool prerelease}) {
  final Object? release = jsonDecode(releaseJson);
  if (release is! Map<String, Object?> || release['isDraft'] is! bool) {
    throw ReleaseException("GitHub's description of $tag isn't one this command can read.");
  }
  if (release['isDraft'] != true) {
    throw ReleaseException(
      '$tag has no draft release. Run Build and tag a release on $releaseBranch to stage it.',
    );
  }
  if (release['isPrerelease'] != prerelease) {
    throw ReleaseException(
      prerelease
          ? '$tag is a prerelease, but its draft is not marked as one. Delete the draft, then '
                're-run the Stage job of the build.'
          : '$tag is not a prerelease, but its draft is marked as one. Delete the draft, then '
                're-run the Stage job of the build.',
    );
  }
}

/// The files in [assets], sorted by name.
List<File> _files(Directory assets) =>
    assets.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));

/// What is wrong with the set of files in [assets] and their checksums.
/// [homebrew] says whether the release has a Homebrew formula.
List<String> _fileProblems(Directory assets, {required bool homebrew}) {
  final Map<String, File> files = {
    for (final File file in _files(assets)) p.basename(file.path): file,
  };
  final File? sha256Sums = files[sha256SumsName];
  if (sha256Sums == null) {
    return ['$sha256SumsName is missing.'];
  }
  final Map<String, String> checksums;
  try {
    checksums = parseSha256Sums(sha256Sums.readAsStringSync());
  } on ReleaseException catch (e) {
    return [e.message];
  }

  final List<String> problems = [];
  for (final String name in [
    for (final ReleaseTarget target in releaseTargets) archiveName(target.name),
    lockfileAsset,
  ]) {
    if (!checksums.containsKey(name)) {
      problems.add('$sha256SumsName does not list $name.');
    }
  }
  final Set<String> expected = {
    ...checksums.keys,
    sha256SumsName,
    installScriptAsset,
    if (homebrew) formulaAsset,
  };
  for (final String name in expected.where((name) => !files.containsKey(name)).toList()..sort()) {
    problems.add('$name is missing.');
  }
  for (final String name in files.keys.where((name) => !expected.contains(name)).toList()..sort()) {
    problems.add('$name is not an asset of the build.');
  }
  for (final MapEntry(key: name, value: checksum) in checksums.entries) {
    final File? file = files[name];
    if (file != null && fileSha256(file) != checksum) {
      problems.add('$name does not match its checksum in $sha256SumsName.');
    }
  }
  return problems;
}

/// Description of the problem with the `skills_lint.rb` in [assets].
///
/// Is `null` if [assets] has no `skills_lint.rb`, or has one that installs
/// [version].
String? _formulaProblem(Directory assets, {required String version}) {
  final formula = File(p.join(assets.path, formulaAsset));
  if (!formula.existsSync()) {
    return null;
  }
  try {
    final String installs = readFormula(
      formula.readAsStringSync().normalizeLineTerminators(),
    ).version;
    return installs == version ? null : '$formulaAsset installs $installs, not $version.';
  } on ReleaseException catch (e) {
    return '$formulaAsset: ${e.message}';
  }
}

/// The URL of the build run in each verification result that
/// `gh attestation verify --format json` printed as [json], or null if
/// [json] isn't in that format.
List<String>? _buildRuns(String json) {
  final Object? results;
  try {
    results = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (results is! List<Object?> || results.isEmpty) {
    return null;
  }
  final List<String> runs = [];
  for (final Object? result in results) {
    // The run that signed the attestation, as gh prints it:
    // verificationResult.signature.certificate.runInvocationURI.
    if (result case {
      'verificationResult': {'signature': {'certificate': {'runInvocationURI': final String run}}},
    }) {
      runs.add(run);
    } else {
      return null;
    }
  }
  return runs;
}
