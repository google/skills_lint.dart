// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Writes the Homebrew formula, `Formula/skills_lint.rb`, from its template
/// and [releaseTargets], and reads back what it wrote.
library;

import 'archive.dart';
import 'macho.dart';
import 'release_exception.dart';
import 'release_info.dart';

/// The `sha256` of each archive until the first release with executables.
final String placeholderSha256 = '0' * 64;

const String _versionPlaceholder = '{{version}}';

const String _platformsPlaceholder = '{{platforms}}';

/// The names that `depends_on macos:` uses. Homebrew names only major macOS
/// versions.
const Map<String, String> _macosNames = {
  '13.0': 'ventura',
  '14.0': 'sonoma',
  '15.0': 'sequoia',
  '26.0': 'tahoe',
};

// `#{version}` is Ruby: the formula fills in its own version.
const String _downloadUrl =
    'https://github.com/google/skills_lint.dart/releases/download/$tagPrefix#{version}';

/// Matches the `version "0.5.3"` line. Group 1 is the version.
final RegExp _versionLine = RegExp(r'^\s*version "([^"]*)"$', multiLine: true);

/// Matches a `url` line and the `sha256` line under it. Group 1 is the
/// archive's file name and group 2 its checksum.
final RegExp _archiveLines = RegExp(r'url "[^"]*/([^"/]+)"\n\s*sha256 "([^"]*)"');

/// The parts of the formula that change with each release.
final class FormulaValues {
  const FormulaValues({required this.version, this.checksums});

  /// The release that the formula installs, such as `0.5.4+1`.
  final String version;

  /// The `sha256` of each archive by file name, or null while the formula
  /// has placeholders.
  final Map<String, String>? checksums;
}

/// Fills in [template] with the version, and the `url` and `sha256` of
/// each of [targets] that Homebrew installs.
///
/// [template] and the result have LF line endings.
///
/// Throws a [ReleaseException] if [template] is missing a placeholder, if
/// [values] has checksums but not one for every archive, or if Homebrew has
/// no name for [macosMinimumVersion].
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
  final List<String> osBlocks = [];
  for (final TargetOs os in TargetOs.values) {
    final List<ReleaseTarget> osTargets = [
      for (final ReleaseTarget target in homebrewTargets(targets))
        if (target.os == os) target,
    ];
    if (osTargets.isNotEmpty) {
      osBlocks.add(_osBlock(os, osTargets, values.checksums));
    }
  }
  return template
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
      '      ${_sha256Line(archive, checksums)}',
      '    end',
    ]);
  }
  lines.add('  end');
  return lines.join('\n');
}

String _sha256Line(String archive, Map<String, String>? checksums) {
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

/// The version and checksums of [formula], which [renderFormula] wrote.
///
/// [formula] has LF line endings.
///
/// Throws a [ReleaseException] if [formula] doesn't have exactly one
/// `version` line or has no archive.
FormulaValues readFormula(String formula) {
  final List<RegExpMatch> versions = _versionLine.allMatches(formula).toList();
  final List<RegExpMatch> archives = _archiveLines.allMatches(formula).toList();
  if (versions.length != 1 || archives.isEmpty) {
    throw ReleaseException(
      'The formula has ${versions.length} version lines and ${archives.length} archives; '
      'expected one version line and at least one archive.',
    );
  }
  final checksums = <String, String>{};
  for (final archive in archives) {
    checksums[archive.group(1)!] = archive.group(2)!;
  }
  final bool placeholders = checksums.values.every((String sha) => sha == placeholderSha256);
  return FormulaValues(
    version: versions.single.group(1)!,
    checksums: placeholders ? null : checksums,
  );
}
