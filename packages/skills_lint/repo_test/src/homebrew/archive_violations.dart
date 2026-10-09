// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../models/convention_violation.dart';
import 'formula_archive.dart';
import 'formula_value.dart';
import 'homebrew_formula.dart';

/// The `sha256` of each archive before the first release with executables.
final String placeholderSha256 = '0' * 64;

/// A well-formed `sha256` value.
final RegExp _sha256Format = RegExp(r'^[0-9a-f]{64}$');

/// The `url` that the formula must give for the archive of [target].
String expectedArchiveUrl(String target) =>
    'https://github.com/google/skills_lint.dart/releases/download/'
    'skills_lint-v#{version}/skills_lint-$target.tar.gz';

/// Reports each way that the archives of [formula] can break `brew install`
/// for one of [targets], the release targets that Homebrew installs.
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
        ConventionViolation(
          path,
          missingStatementLine,
          'has no block for the release target $target',
        ),
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
    formula.version?.line ?? missingStatementLine,
    'replace every placeholder in one change: the version and all sha256 values are '
    'placeholders, or none are',
  );
}
