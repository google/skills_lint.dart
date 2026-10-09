// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Generates the Homebrew formula, `Formula/skills_lint.rb`, from its
/// template and [releaseTargets], and checks the committed formula.
library;

import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

import 'archive.dart';
import 'macho.dart';
import 'release_exception.dart';
import 'release_info.dart';

/// The `sha256` of each archive while the formula waits for its first
/// release with executables.
final String placeholderSha256 = '0' * 64;

/// The template line that the per-target `url` and `sha256` blocks replace.
const String _platformsPlaceholder = '{{platforms}}';

/// The template text that the version replaces.
const String _versionPlaceholder = '{{version}}';

/// The name that `depends_on macos:` gives each macOS version that
/// [macosMinimumVersion] can be. Homebrew names major versions only.
const Map<String, String> _macosNames = {
  '13.0': 'ventura',
  '14.0': 'sonoma',
  '15.0': 'sequoia',
  '26.0': 'tahoe',
};

/// The download URL of a release asset, up to the file name. `#{version}`
/// is Ruby: the formula fills in its own version.
const String _downloadUrl =
    'https://github.com/google/skills_lint.dart/releases/download/$tagPrefix#{version}';

/// A `version` statement, such as `  version "0.5.3"`, with an optional
/// trailing comment. Group 1 is the version.
final RegExp _versionStatement = RegExp(r'^\s*version "([^"]*)"(\s*#.*)?$', multiLine: true);

/// A `url` line and the `sha256` line after it. Group 1 is the file name at
/// the end of the url, and group 2 the checksum.
final RegExp _archiveStatements = RegExp(r'url "[^"]*/([^"/]+)"\n\s*sha256 "([^"]*)"');

/// The values of the formula that change from release to release.
final class FormulaValues {
  const FormulaValues({required this.version, this.checksums});

  /// The release that the formula installs, such as `0.5.4+1`.
  final String version;

  /// The `sha256` of each archive keyed by its file name, or null while the
  /// formula has placeholders.
  final Map<String, String>? checksums;
}

/// The formula that [template] gives for [values], with a block for each
/// target of [targets] that Homebrew can install.
///
/// Throws a [ReleaseException] if [template] lacks a placeholder, if
/// [values] has checksums but none for one of the archives, or if
/// [macosMinimumVersion] has no Homebrew name.
String renderFormula(
  String template,
  FormulaValues values, {
  List<ReleaseTarget> targets = releaseTargets,
}) {
  for (final String placeholder in [_versionPlaceholder, _platformsPlaceholder]) {
    if (!template.contains(placeholder)) {
      throw ReleaseException('The formula template has no $placeholder.');
    }
  }
  final Map<TargetOs, List<ReleaseTarget>> targetsByOs = {};
  for (final ReleaseTarget target in homebrewTargets(targets)) {
    targetsByOs.putIfAbsent(target.os, () => []).add(target);
  }
  final List<String> osBlocks = [
    for (final MapEntry(key: os, value: osTargets) in targetsByOs.entries)
      _osBlock(os, osTargets, values.checksums),
  ];
  return _withLf(template)
      .replaceAll(_versionPlaceholder, values.version)
      .replaceFirst(_platformsPlaceholder, osBlocks.join('\n\n'));
}

/// The `on_<os>` block for [os], with an `on_<arch>` block for each of
/// [targets].
String _osBlock(TargetOs os, List<ReleaseTarget> targets, Map<String, String>? checksums) {
  final lines = ['  ${os.homebrewBlock} do'];
  // Outside on_macos, depends_on macos: would stop Linux installs.
  if (os == TargetOs.macos) {
    lines
      ..add('    depends_on macos: :${_macosName()}')
      ..add('');
  }
  for (final target in targets) {
    final String archive = archiveName(target.name);
    lines.addAll([
      '    ${target.arch.homebrewBlock} do',
      '      url "$_downloadUrl/$archive"',
      '      ${_sha256Statement(archive, checksums)}',
      '    end',
    ]);
  }
  lines.add('  end');
  return lines.join('\n');
}

String _sha256Statement(String archive, Map<String, String>? checksums) {
  if (checksums == null) {
    return 'sha256 "$placeholderSha256" # PLACEHOLDER';
  }
  final String? checksum = checksums[archive];
  if (checksum == null) {
    throw ReleaseException('There is no checksum for $archive.');
  }
  return 'sha256 "$checksum"';
}

String _macosName() {
  final String? name = _macosNames[macosMinimumVersion];
  if (name == null) {
    throw ReleaseException(
      'Homebrew has no name for macOS $macosMinimumVersion in _macosNames in '
      'release/lib/src/homebrew_formula.dart. Add it.',
    );
  }
  return name;
}

/// The version and checksums in [formula], a formula that [renderFormula]
/// wrote.
///
/// Throws a [ReleaseException] if [formula] doesn't have exactly one
/// `version` or has no archive.
FormulaValues readFormula(String formula) {
  final String text = _withLf(formula);
  final List<RegExpMatch> versions = _versionStatement.allMatches(text).toList();
  final List<RegExpMatch> archives = _archiveStatements.allMatches(text).toList();
  if (versions.length != 1 || archives.isEmpty) {
    throw ReleaseException(
      'The formula has ${versions.length} version lines and ${archives.length} archives; '
      'expected one version line and at least one archive.',
    );
  }
  final Map<String, String> checksums = {
    for (final RegExpMatch archive in archives) archive.group(1)!: archive.group(2)!,
  };
  final bool placeholders = checksums.values.every((String sha) => sha == placeholderSha256);
  return FormulaValues(
    version: versions.single.group(1)!,
    checksums: placeholders ? null : checksums,
  );
}

/// Each way that [formula] differs from what [template] gives for its own
/// version and checksums, and each way its version breaks the release rules
/// against [pubspecVersion] and [changelog].
///
/// While the formula has placeholders, its version is the pubspec version
/// without `-wip`, the release the placeholders wait for. After that, it is
/// a release: [changelog] has a `## <version>` heading for it, and it is not
/// newer than the pubspec version.
List<String> formulaProblems(
  String formula, {
  required String template,
  required String pubspecVersion,
  required String changelog,
  List<ReleaseTarget> targets = releaseTargets,
}) {
  final FormulaValues values = readFormula(formula);
  final List<String> problems = [..._versionProblems(values, pubspecVersion, changelog)];
  final String expected = renderFormula(template, values, targets: targets);
  final String? difference = _firstDifference(expected: expected, actual: _withLf(formula));
  if (difference != null) {
    problems.add(difference);
  }
  return problems;
}

List<String> _versionProblems(FormulaValues values, String pubspecVersion, String changelog) {
  final String version = values.version;
  if (!isHomebrewVersion(version)) {
    return ['version "$version" is not a release that Homebrew can install'];
  }
  if (values.checksums == null) {
    final String pendingRelease = pubspecVersion.replaceFirst('-wip', '');
    if (version == pendingRelease) {
      return [];
    }
    const rule = 'the pubspec version without -wip';
    return ['placeholder version "$version" must be $pendingRelease, $rule ($pubspecVersion)'];
  }
  final bool released = LineSplitter.split(
    changelog,
  ).any((String line) => line.trim() == '## $version');
  return [
    if (!released) 'version "$version" has no "## $version" heading in the CHANGELOG',
    if (Version.parse(version) > Version.parse(pubspecVersion))
      'version "$version" is newer than the pubspec version $pubspecVersion',
  ];
}

/// The first line where [actual] differs from [expected], or null if they
/// are the same.
String? _firstDifference({required String expected, required String actual}) {
  final List<String> expectedLines = LineSplitter.split(expected).toList();
  final List<String> actualLines = LineSplitter.split(actual).toList();
  for (var i = 0; i < expectedLines.length || i < actualLines.length; i++) {
    final String? want = i < expectedLines.length ? expectedLines[i] : null;
    final String? got = i < actualLines.length ? actualLines[i] : null;
    if (want != got) {
      return 'line ${i + 1} is ${got ?? 'missing'}; the template gives ${want ?? 'nothing'}';
    }
  }
  return null;
}

/// [text] with LF line endings. A Windows checkout can give the template and
/// the formula CRLF endings.
String _withLf(String text) => text.replaceAll('\r\n', '\n');
