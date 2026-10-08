// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Reads the Homebrew formula in `Formula/skills_lint.rb` and reports where
/// it disagrees with the release archives, the package version or the
/// minimum macOS version of the executables.
///
/// The offline `brew audit` accepts a formula whose `on_arm` block names the
/// x64 archive, whose archives share a `sha256`, or whose `version` is not a
/// release in the CHANGELOG. Each of these breaks `brew install` on some
/// platform.
///
/// The reader handles the subset of Ruby that the formula uses: one
/// statement per line, `do`/`end` blocks, and string literals without
/// escapes. It stops at the first `def`, so it never reads the `install` or
/// `test` code.
library;

import 'package:pub_semver/pub_semver.dart';

import 'models/convention_violation.dart';

/// The `sha256` of each archive before the first release with executables.
final String placeholderSha256 = '0' * 64;

/// The comment that marks each line whose value is a placeholder.
const String placeholderMarker = '# PLACEHOLDER';

/// The major version of each macOS that `depends_on macos:` can name.
///
/// Add the next macOS here when `macosMinimumVersion` in
/// `release/lib/src/macho.dart` moves to it.
const Map<String, int> macosSymbolMajors = {
  'ventura': 13,
  'sonoma': 14,
  'sequoia': 15,
  'tahoe': 26,
};

/// The operating system in a target name, for each block that selects one.
const Map<String, String> _osBlocks = {'on_macos': 'macos', 'on_linux': 'linux'};

/// The architecture in a target name, for each block that selects one.
const Map<String, String> _archBlocks = {'on_arm': 'arm64', 'on_intel': 'x64'};

/// A line that opens a block, such as `on_macos do` or
/// `assert_predicate x do |y|`. Group 1 is the first word.
final RegExp _blockStart = RegExp(r'^(\w+)\b.*\sdo(\s*\|[^|]*\|)?$');

/// A `version`, `url` or `sha256` statement, such as
/// `sha256 "0000…" # PLACEHOLDER`. Group 1 is the keyword and group 2 is the
/// string.
final RegExp _stringStatement = RegExp(r'^(version|url|sha256) "([^"\\]*)"');

/// A macOS dependency, such as `depends_on macos: :sonoma`. Group 1 is the
/// symbol.
final RegExp _macosDependency = RegExp(r'^depends_on macos: :(\w+)');

/// A well-formed `sha256` value.
final RegExp _sha256Format = RegExp(r'^[0-9a-f]{64}$');

/// The line of a violation about a statement that the formula lacks. The
/// statement has no line, so the violation points at the top of the file.
const int _topOfFile = 1;

/// The `url` that the formula must give for the archive of [target].
String expectedArchiveUrl(String target) =>
    'https://github.com/google/skills_lint.dart/releases/download/'
    'skills_lint-v#{version}/skills_lint-$target.tar.gz';

/// One value in the formula, the 1-based line it is on, and whether that
/// line has [placeholderMarker].
typedef FormulaValue = ({String value, int line, bool placeholder});

/// The `url` and `sha256` lines inside one `on_<os>` and `on_<arch>` block
/// pair.
final class FormulaArchive {
  FormulaArchive(this.target, this.line);

  /// `<os>-<arch>`, such as `macos-arm64`.
  final String target;

  /// The line of the first `url` or `sha256` in the block.
  final int line;

  /// A valid block has one.
  final List<FormulaValue> urls = [];

  /// A valid block has one.
  final List<FormulaValue> sha256s = [];
}

/// What [parseFormula] read from a formula.
final class HomebrewFormula {
  FormulaValue? version;

  /// The symbol of `depends_on macos:`, such as `sonoma`.
  FormulaValue? macosMinimum;

  /// Whether [macosMinimum] is inside `on_macos`. Outside it, Homebrew
  /// refuses to install the formula on Linux.
  bool macosMinimumOnMacosOnly = false;

  /// The archives by target, in file order.
  final Map<String, FormulaArchive> archives = {};

  /// Each `url` or `sha256` that no `on_<os>` and `on_<arch>` block pair
  /// encloses.
  final List<FormulaValue> unscopedValues = [];

  /// Every `sha256` of [archives], in file order.
  List<FormulaValue> get sha256s {
    final List<FormulaValue> all = [];
    for (final FormulaArchive archive in archives.values) {
      all.addAll(archive.sha256s);
    }
    return all;
  }

  bool get hasPlaceholders {
    final bool versionIsPlaceholder = version?.placeholder ?? false;
    return versionIsPlaceholder || sha256s.any((FormulaValue sha) => sha.placeholder);
  }
}

/// Reads the version, the archives and the macOS dependency of [content], a
/// formula.
HomebrewFormula parseFormula(String content) {
  final formula = HomebrewFormula();
  final List<String> openBlocks = [];
  final List<String> lines = content.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final String line = lines[index].trim();
    final int lineNumber = index + 1;
    if (line.startsWith('def ')) {
      break;
    }
    final RegExpMatch? blockStart = _blockStart.firstMatch(line);
    if (blockStart != null) {
      openBlocks.add(blockStart.group(1)!);
    } else if (line == 'end' && openBlocks.isNotEmpty) {
      openBlocks.removeLast();
    } else {
      _readStatement(formula, openBlocks, line, lineNumber);
    }
  }
  return formula;
}

/// Records [line] in [formula] if it is a statement that the checks read.
void _readStatement(HomebrewFormula formula, List<String> openBlocks, String line, int lineNumber) {
  final bool isPlaceholder = line.contains(placeholderMarker);

  final RegExpMatch? macosDependency = _macosDependency.firstMatch(line);
  if (macosDependency != null) {
    final String symbol = macosDependency.group(1)!;
    formula.macosMinimum = (value: symbol, line: lineNumber, placeholder: isPlaceholder);
    formula.macosMinimumOnMacosOnly = openBlocks.contains('on_macos');
    return;
  }

  final RegExpMatch? statement = _stringStatement.firstMatch(line);
  if (statement == null) {
    return;
  }
  final String keyword = statement.group(1)!;
  final FormulaValue value = (
    value: statement.group(2)!,
    line: lineNumber,
    placeholder: isPlaceholder,
  );
  if (keyword == 'version') {
    formula.version = value;
    return;
  }

  final String? target = _selectedTarget(openBlocks);
  if (target == null) {
    formula.unscopedValues.add(value);
    return;
  }
  final FormulaArchive archive = formula.archives.putIfAbsent(
    target,
    () => FormulaArchive(target, lineNumber),
  );
  if (keyword == 'url') {
    archive.urls.add(value);
  } else {
    archive.sha256s.add(value);
  }
}

/// The `<os>-<arch>` that [openBlocks] select, or null unless they select
/// both an operating system and an architecture.
String? _selectedTarget(List<String> openBlocks) {
  String? os;
  String? arch;
  for (final block in openBlocks) {
    os = _osBlocks[block] ?? os;
    arch = _archBlocks[block] ?? arch;
  }
  if (os == null || arch == null) {
    return null;
  }
  return '$os-$arch';
}

/// Reports each difference between the archives of [formula] and
/// [targets], the release targets that Homebrew installs.
///
/// Each target needs one block with its exact `url` and one `sha256`. Every
/// `sha256` is either a placeholder with [placeholderMarker], or real and
/// different from the others. The version and the checksums are either all
/// placeholders or none, because the Homebrew workflow installs the formula
/// only once it has no placeholder.
List<ConventionViolation> findArchiveViolations(
  String path,
  HomebrewFormula formula,
  List<String> targets,
) {
  final List<ConventionViolation> violations = [];
  for (final FormulaValue value in formula.unscopedValues) {
    violations.add(
      ConventionViolation(
        path,
        value.line,
        '"${value.value}" is outside an on_macos/on_linux and on_arm/on_intel block',
      ),
    );
  }
  for (final target in targets) {
    if (!formula.archives.containsKey(target)) {
      violations.add(
        ConventionViolation(path, _topOfFile, 'has no block for the release target $target'),
      );
    }
  }
  for (final FormulaArchive archive in formula.archives.values) {
    violations.addAll(_blockViolations(path, archive, targets));
  }
  violations.addAll(_sha256Violations(path, formula.sha256s));
  final ConventionViolation? mixed = _mixedPlaceholderViolation(path, formula);
  if (mixed != null) {
    violations.add(mixed);
  }
  return violations;
}

/// Reports a block for a target that is not released, a block without
/// exactly one `url` and one `sha256`, and a `url` for another archive.
List<ConventionViolation> _blockViolations(
  String path,
  FormulaArchive archive,
  List<String> targets,
) {
  final String target = archive.target;
  if (!targets.contains(target)) {
    return [
      ConventionViolation(
        path,
        archive.line,
        'has a block for $target, which is not a release target',
      ),
    ];
  }
  final List<ConventionViolation> violations = [];
  final int urlCount = archive.urls.length;
  final int sha256Count = archive.sha256s.length;
  if (urlCount != 1 || sha256Count != 1) {
    violations.add(
      ConventionViolation(
        path,
        archive.line,
        'the $target block has $urlCount url and $sha256Count sha256 lines; expected one of each',
      ),
    );
  }
  final String expectedUrl = expectedArchiveUrl(target);
  for (final FormulaValue url in archive.urls) {
    if (url.value != expectedUrl) {
      violations.add(
        ConventionViolation(
          path,
          url.line,
          'the $target url is "${url.value}"; expected "$expectedUrl"',
        ),
      );
    }
  }
  return violations;
}

/// Reports each malformed `sha256`, each one whose zeros and marker
/// disagree, and each real one that another archive repeats.
List<ConventionViolation> _sha256Violations(String path, List<FormulaValue> sha256s) {
  final List<ConventionViolation> violations = [];
  final Set<String> seenRealValues = {};
  for (final sha in sha256s) {
    final isZeros = sha.value == placeholderSha256;
    if (!_sha256Format.hasMatch(sha.value)) {
      violations.add(
        ConventionViolation(path, sha.line, 'sha256 "${sha.value}" is not 64 lowercase hex digits'),
      );
    } else if (isZeros != sha.placeholder) {
      violations.add(
        ConventionViolation(
          path,
          sha.line,
          'a sha256 is 64 zeros if and only if its line has $placeholderMarker',
        ),
      );
    } else if (!isZeros && !seenRealValues.add(sha.value)) {
      violations.add(
        ConventionViolation(
          path,
          sha.line,
          'sha256 ${sha.value} is also the sha256 of another archive',
        ),
      );
    }
  }
  return violations;
}

/// Reports a formula whose version and checksums are not all placeholders
/// or all real.
ConventionViolation? _mixedPlaceholderViolation(String path, HomebrewFormula formula) {
  final List<FormulaValue> sha256s = formula.sha256s;
  final int placeholderCount = sha256s.where((FormulaValue sha) => sha.placeholder).length;
  final bool anySha256IsPlaceholder = placeholderCount > 0;
  final bool sha256sDisagree = anySha256IsPlaceholder && placeholderCount != sha256s.length;
  final bool versionIsPlaceholder = formula.version?.placeholder ?? false;
  final versionDisagrees = versionIsPlaceholder != anySha256IsPlaceholder;
  if (!sha256sDisagree && !versionDisagrees) {
    return null;
  }
  return ConventionViolation(
    path,
    formula.version?.line ?? _topOfFile,
    'replace every placeholder in one change: the version and all sha256 values are '
    'placeholders, or none are',
  );
}

/// Reports where the `version` of [formula] breaks the version rule.
///
/// The version is never a prerelease, because Homebrew installs it for every
/// user; a version with build metadata, such as `1.2.0+1`, is a release.
/// While the formula has placeholders, the version is [pubspecVersion]
/// without `-wip`, the release that the placeholders wait for. Once the values are real, the version is a
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
    return [ConventionViolation(path, _topOfFile, 'has no version')];
  }
  final String? problem = _versionProblem(
    version.value,
    formulaHasPlaceholders: formula.hasPlaceholders,
    pubspec: Version.parse(pubspecVersion),
    changelog: changelog,
  );
  if (problem == null) {
    return [];
  }
  return [ConventionViolation(path, version.line, problem)];
}

String? _versionProblem(
  String value, {
  required bool formulaHasPlaceholders,
  required Version pubspec,
  required String changelog,
}) {
  final Version version;
  try {
    version = Version.parse(value);
  } on FormatException {
    return 'version "$value" is not a semantic version';
  }
  if (version.isPreRelease) {
    return 'version "$value" is a prerelease; Homebrew installs releases only';
  }
  if (formulaHasPlaceholders) {
    final String pendingRelease = '$pubspec'.replaceFirst('-wip', '');
    if (value == pendingRelease) {
      return null;
    }
    return 'placeholder version "$value" must be $pendingRelease, the pubspec version $pubspec '
        'without -wip';
  }
  final bool changelogHasHeading = changelog
      .split('\n')
      .any((String line) => line.trim() == '## $value');
  if (!changelogHasHeading) {
    return 'version "$value" has no "## $value" heading in the CHANGELOG, so it is not a release';
  }
  if (version > pubspec) {
    return 'version "$value" is newer than the pubspec version $pubspec';
  }
  return null;
}

/// Reports where the `depends_on macos:` of [formula] is missing, outside
/// `on_macos`, or names another macOS than [minimumVersion], the minimum
/// macOS version of the executables.
///
/// Homebrew names major versions only, so [minimumVersion] must be
/// `<major>.0`. A null [minimumVersion] skips that comparison.
List<ConventionViolation> findMacosViolations(
  String path,
  HomebrewFormula formula,
  String? minimumVersion,
) {
  final FormulaValue? dependency = formula.macosMinimum;
  if (dependency == null) {
    return [ConventionViolation(path, _topOfFile, 'has no depends_on macos: inside on_macos')];
  }
  final List<ConventionViolation> violations = [];
  if (!formula.macosMinimumOnMacosOnly) {
    violations.add(
      ConventionViolation(
        path,
        dependency.line,
        'depends_on macos: is outside on_macos, so Linux cannot install',
      ),
    );
  }
  final String symbol = dependency.value;
  final int? major = macosSymbolMajors[symbol];
  if (major == null) {
    violations.add(
      ConventionViolation(path, dependency.line, ':$symbol is not in macosSymbolMajors'),
    );
  } else if (minimumVersion != null && '$major.0' != minimumVersion) {
    violations.add(
      ConventionViolation(
        path,
        dependency.line,
        ':$symbol is macOS $major.0, but the executables need macOS $minimumVersion',
      ),
    );
  }
  return violations;
}
