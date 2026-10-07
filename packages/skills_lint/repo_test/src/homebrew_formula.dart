// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Reads the Homebrew formula in `Formula/skills_lint.rb` and reports where
/// it disagrees with the release archives, the package version or the
/// minimum macOS version of the executables.
///
/// The formula is Ruby, and `brew audit` checks only that it is a valid
/// formula. It cannot tell that an `on_arm` block names the x64 archive, that
/// a `sha256` belongs to another archive, or that `version` names a release
/// that does not exist. Any of these breaks `brew install` for some users
/// and passes every Homebrew check until someone installs on that platform.
///
/// The reader handles the subset of Ruby that the formula uses: one
/// statement per line, `do`/`end` blocks, and string literals without
/// escapes. It stops at the first `def`, so it never reads the `install` or
/// `test` code. Change it if the formula needs a construct outside that
/// subset, such as a `url` built from a helper method.
library;

import 'package:pub_semver/pub_semver.dart';

import 'models/convention_violation.dart';

/// A 64-zero `sha256`, which marks an archive that no release has yet.
final String placeholderSha256 = '0' * 64;

/// The marker comment on each placeholder value in the formula.
const String placeholderMarker = '# PLACEHOLDER';

/// The macOS versions that Homebrew names in `depends_on macos:`, for the
/// releases that the executables can target.
///
/// Add the next release's symbol here when `macosMinimumVersion` in
/// `release/lib/src/macho.dart` moves to it.
const Map<String, int> macosSymbolMajors = {
  'ventura': 13,
  'sonoma': 14,
  'sequoia': 15,
  'tahoe': 26,
};

/// The operating systems and CPU architectures that a Homebrew formula can
/// select an archive for, mapped from the `on_<name>` block that selects
/// each one.
///
/// Homebrew runs on macOS and Linux only, and its formula DSL has `on_arm`
/// and `on_intel` but no block for any other architecture. A release target
/// outside these, such as `windows-x64` or `linux-riscv64`, has no formula
/// block.
const Map<String, String> formulaOperatingSystems = {'on_macos': 'macos', 'on_linux': 'linux'};

/// See [formulaOperatingSystems].
const Map<String, String> formulaArchitectures = {'on_arm': 'arm64', 'on_intel': 'x64'};

/// The `url` that the formula must give for the archive of [target].
String expectedArchiveUrl(String target) =>
    'https://github.com/google/skills_lint.dart/releases/download/'
    'skills_lint-v#{version}/skills_lint-$target.tar.gz';

/// Returns the [targets] that a Homebrew formula can install, in order.
///
/// A target is `<os>-<arch>`. See [formulaOperatingSystems].
List<String> formulaTargets(Iterable<String> targets) => [
  for (final target in targets)
    if (target.split('-') case [
      final os,
      final arch,
    ] when formulaOperatingSystems.containsValue(os) && formulaArchitectures.containsValue(arch))
      target,
];

/// One value in the formula: what it says and the 1-based line it is on.
typedef FormulaValue = ({String value, int line, bool placeholder});

/// The archive that one `on_<os>` and `on_<arch>` block pair selects.
final class FormulaArchive {
  FormulaArchive(this.target, this.line);

  /// `<os>-<arch>`, such as `macos-arm64`.
  final String target;

  /// 1-based line of the first `url` or `sha256` in the block.
  final int line;

  /// Every `url` in the block. A valid block has one.
  final List<FormulaValue> urls = [];

  /// Every `sha256` in the block. A valid block has one.
  final List<FormulaValue> sha256s = [];
}

/// What [parseFormula] read from a formula.
final class HomebrewFormula {
  /// The `version`, or null if the formula has none.
  FormulaValue? version;

  /// The `depends_on macos:` symbol, such as `sonoma`, or null if the formula
  /// has none.
  FormulaValue? macosMinimum;

  /// Whether [macosMinimum] is inside an `on_macos` block. Outside one,
  /// Homebrew refuses to install the formula on Linux.
  bool macosMinimumOnMacosOnly = false;

  /// The archives, keyed by target, in file order.
  final Map<String, FormulaArchive> archives = {};

  /// Each `url` or `sha256` outside an `on_<os>` and `on_<arch>` block pair.
  final List<FormulaValue> unscopedValues = [];

  /// Whether any value is a placeholder.
  bool get hasPlaceholders =>
      (version?.placeholder ?? false) ||
      archives.values.any((archive) => archive.sha256s.any((sha) => sha.placeholder));
}

final RegExp _blockStart = RegExp(r'^(\w+)\b.*\sdo(\s*\|[^|]*\|)?$');
final RegExp _stringValue = RegExp(r'^(version|url|sha256) "([^"\\]*)"');
final RegExp _macosDependency = RegExp(r'^depends_on macos: :(\w+)');

/// Reads the version, the archives and the macOS dependency of [content], a
/// formula. See the library comment for the Ruby that it understands.
HomebrewFormula parseFormula(String content) {
  final formula = HomebrewFormula();
  final List<String> blocks = [];
  final List<String> lines = content.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final String line = lines[index].trim();
    if (line.startsWith('def ')) {
      break;
    }
    if (_blockStart.firstMatch(line) case final RegExpMatch match) {
      blocks.add(match.group(1)!);
    } else if (line == 'end' && blocks.isNotEmpty) {
      blocks.removeLast();
    } else {
      _readStatement(formula, blocks, line, index + 1);
    }
  }
  return formula;
}

void _readStatement(HomebrewFormula formula, List<String> blocks, String line, int number) {
  final bool placeholder = line.contains(placeholderMarker);
  if (_macosDependency.firstMatch(line) case final RegExpMatch match) {
    formula.macosMinimum = (value: match.group(1)!, line: number, placeholder: placeholder);
    formula.macosMinimumOnMacosOnly = blocks.contains('on_macos');
    return;
  }
  final RegExpMatch? match = _stringValue.firstMatch(line);
  if (match == null) {
    return;
  }
  final FormulaValue value = (value: match.group(2)!, line: number, placeholder: placeholder);
  if (match.group(1) == 'version') {
    formula.version = value;
    return;
  }
  final String? target = _target(blocks);
  if (target == null) {
    formula.unscopedValues.add(value);
    return;
  }
  final FormulaArchive archive = formula.archives[target] ??= FormulaArchive(target, number);
  (match.group(1) == 'url' ? archive.urls : archive.sha256s).add(value);
}

/// The `<os>-<arch>` that the open [blocks] select, or null if they do not
/// select both.
String? _target(List<String> blocks) {
  final String? os = blocks.map((block) => formulaOperatingSystems[block]).nonNulls.lastOrNull;
  final String? arch = blocks.map((block) => formulaArchitectures[block]).nonNulls.lastOrNull;
  return os == null || arch == null ? null : '$os-$arch';
}

/// Reports each difference between the archives of [formula] and
/// [targets], the release targets that a formula can install.
///
/// Each target needs one block with its exact `url` and one `sha256`. Every
/// `sha256` is either a placeholder with [placeholderMarker], or real and
/// different from the others. Either all of them are placeholders or none
/// are, because the Homebrew workflow installs the formula only once it has
/// no placeholder.
List<ConventionViolation> findArchiveViolations(
  String path,
  HomebrewFormula formula,
  List<String> targets,
) {
  ConventionViolation at(int line, String problem) => ConventionViolation(path, line, problem);
  return [
    for (final FormulaValue value in formula.unscopedValues)
      at(value.line, '"${value.value}" is outside an on_macos/on_linux and on_arm/on_intel block'),
    for (final String target in targets)
      if (!formula.archives.containsKey(target))
        at(1, 'has no block for the release target $target'),
    for (final FormulaArchive archive in formula.archives.values)
      ..._archiveProblems(archive, targets, at),
    ..._sha256Problems(formula, at),
  ];
}

Iterable<ConventionViolation> _archiveProblems(
  FormulaArchive archive,
  List<String> targets,
  ConventionViolation Function(int, String) at,
) sync* {
  if (!targets.contains(archive.target)) {
    yield at(archive.line, 'has a block for ${archive.target}, which is not a release target');
    return;
  }
  if (archive.urls.length != 1 || archive.sha256s.length != 1) {
    yield at(
      archive.line,
      'the ${archive.target} block has ${archive.urls.length} url and '
      '${archive.sha256s.length} sha256 lines; expected one of each',
    );
  }
  final String expected = expectedArchiveUrl(archive.target);
  for (final FormulaValue url in archive.urls) {
    if (url.value != expected) {
      yield at(url.line, 'the ${archive.target} url is "${url.value}"; expected "$expected"');
    }
  }
}

Iterable<ConventionViolation> _sha256Problems(
  HomebrewFormula formula,
  ConventionViolation Function(int, String) at,
) sync* {
  final List<FormulaValue> sha256s = [
    for (final FormulaArchive archive in formula.archives.values) ...archive.sha256s,
  ];
  final Set<String> seen = {};
  for (final sha in sha256s) {
    final zeros = sha.value == placeholderSha256;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha.value)) {
      yield at(sha.line, 'sha256 "${sha.value}" is not 64 lowercase hex digits');
    } else if (zeros != sha.placeholder) {
      yield at(
        sha.line,
        'a sha256 is 64 zeros if and only if its line ends with $placeholderMarker',
      );
    } else if (!zeros && !seen.add(sha.value)) {
      yield at(sha.line, 'sha256 ${sha.value} is also the sha256 of another archive');
    }
  }
  final int placeholders = sha256s.where((sha) => sha.placeholder).length;
  final bool versionPlaceholder = formula.version?.placeholder ?? false;
  if (placeholders != 0 && placeholders != sha256s.length ||
      versionPlaceholder != (placeholders > 0)) {
    yield at(
      formula.version?.line ?? 1,
      'replace every placeholder in one change: the version and all sha256 values are '
      'placeholders, or none are',
    );
  }
}

/// Reports where the `version` of [formula] breaks the version rule.
///
/// The version is never a prerelease, because Homebrew installs it for every
/// user. While the formula has placeholders, the version is
/// [pubspecVersion] without its prerelease suffix, the release that the
/// placeholders wait for. Once the values are real, the version is a
/// release: [changelog] has a `## <version>` heading for it, and it is not
/// newer than [pubspecVersion].
List<ConventionViolation> findVersionViolations(
  String path,
  HomebrewFormula formula, {
  required String pubspecVersion,
  required String changelog,
}) {
  final FormulaValue? version = formula.version;
  if (version == null) {
    return [ConventionViolation(path, 1, 'has no version')];
  }
  final String? problem = _versionProblem(
    formula,
    version.value,
    Version.parse(pubspecVersion),
    changelog,
  );
  return [if (problem != null) ConventionViolation(path, version.line, problem)];
}

String? _versionProblem(HomebrewFormula formula, String value, Version pubspec, String changelog) {
  final Version version;
  try {
    version = Version.parse(value);
  } on FormatException {
    return 'version "$value" is not a semantic version';
  }
  if (version.isPreRelease || version.build.isNotEmpty) {
    return 'version "$value" is a prerelease; Homebrew installs releases only';
  }
  if (formula.hasPlaceholders) {
    final release = Version(pubspec.major, pubspec.minor, pubspec.patch);
    return version == release
        ? null
        : 'placeholder version "$value" must be $release, the pubspec version $pubspec without its suffix';
  }
  if (!changelog.split('\n').any((line) => line.trim() == '## $value')) {
    return 'version "$value" has no "## $value" heading in the CHANGELOG, so it is not a release';
  }
  return version > pubspec ? 'version "$value" is newer than the pubspec version $pubspec' : null;
}

/// Reports where the `depends_on macos:` of [formula] is missing, misplaced
/// or disagrees with [minimumVersion], the minimum macOS version of the
/// executables.
///
/// The dependency must be inside `on_macos`, or Homebrew refuses to install
/// the formula on Linux. Homebrew names major versions only, so
/// [minimumVersion] must be `<major>.0`. A null [minimumVersion] skips that
/// comparison.
List<ConventionViolation> findMacosViolations(
  String path,
  HomebrewFormula formula,
  String? minimumVersion,
) {
  final FormulaValue? dependency = formula.macosMinimum;
  if (dependency == null) {
    return [ConventionViolation(path, 1, 'has no depends_on macos: inside on_macos')];
  }
  final int? major = macosSymbolMajors[dependency.value];
  return [
    if (!formula.macosMinimumOnMacosOnly)
      ConventionViolation(
        path,
        dependency.line,
        'depends_on macos: is outside on_macos, so Linux cannot install',
      ),
    if (major == null)
      ConventionViolation(path, dependency.line, ':${dependency.value} is not in macosSymbolMajors')
    else if (minimumVersion != null && '$major.0' != minimumVersion)
      ConventionViolation(
        path,
        dependency.line,
        ':${dependency.value} is macOS $major.0, but the executables need macOS $minimumVersion',
      ),
  ];
}
