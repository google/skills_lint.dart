// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/homebrew_formula.dart';
import 'package:skills_lint_release/src/paths.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:test/test.dart';

final String _zeros = '0' * 64;
final String _arm = 'a' * 64;
final String _intel = 'b' * 64;

const String _base =
    'https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}';

/// A formula in the format of `Formula/skills_lint.rb` with placeholders.
final String _placeholderFormula =
    '''
# typed: strict

# Homebrew formula for the prebuilt skills_lint executables.
# RELEASING.md says how this file is checked and how to update it.
#
# PLACEHOLDER: no release has the executables yet. `version` and every
# `sha256` below are placeholders.
class SkillsLint < Formula
  version "0.5.3" # PLACEHOLDER: set to the first release with executables.

  livecheck do
    url :stable
  end

  on_macos do
    on_arm do
      url "$_base/skills_lint-macos-arm64.tar.gz"
      sha256 "$_zeros" # PLACEHOLDER
    end
    on_intel do
      url "$_base/skills_lint-macos-x64.tar.gz"
      sha256 "$_zeros" # PLACEHOLDER
    end
  end
end
''';

final String _releasedFormula =
    '''
# typed: strict

# Homebrew formula for the prebuilt skills_lint executables.
# RELEASING.md says how this file is checked and how to update it.
class SkillsLint < Formula
  version "0.6.0"

  livecheck do
    url :stable
  end

  on_macos do
    on_arm do
      url "$_base/skills_lint-macos-arm64.tar.gz"
      sha256 "$_arm"
    end
    on_intel do
      url "$_base/skills_lint-macos-x64.tar.gz"
      sha256 "$_intel"
    end
  end
end
''';

final Map<String, String> _checksums = {
  'skills_lint-macos-arm64.tar.gz': _arm,
  'skills_lint-macos-x64.tar.gz': _intel,
  'pubspec.lock': 'c' * 64,
};

void main() {
  group('updateFormula', () {
    test('fills in the first release and removes every PLACEHOLDER comment', () {
      expect(
        updateFormula(_placeholderFormula, version: '0.6.0', checksums: _checksums),
        _releasedFormula,
      );
    });

    test('updates a released formula to the next release', () {
      final String next = updateFormula(
        _releasedFormula,
        version: '0.6.1',
        checksums: {'skills_lint-macos-arm64.tar.gz': _intel, 'skills_lint-macos-x64.tar.gz': _arm},
      );
      expect(next, contains('version "0.6.1"'));
      expect(next, contains('macos-arm64.tar.gz"\n      sha256 "$_intel"'));
      expect(next, contains('macos-x64.tar.gz"\n      sha256 "$_arm"'));
    });

    test('accepts a version with build metadata', () {
      final String next = updateFormula(
        _releasedFormula,
        version: '0.6.0+1',
        checksums: _checksums,
      );
      expect(next, contains('version "0.6.0+1"\n'));
    });

    test('takes each checksum from the archive that the url above it names', () {
      final String swapped = _placeholderFormula
          .replaceFirst('macos-arm64.tar.gz', 'TEMP')
          .replaceFirst('macos-x64.tar.gz', 'macos-arm64.tar.gz')
          .replaceFirst('TEMP', 'macos-x64.tar.gz');
      final String updated = updateFormula(swapped, version: '0.6.0', checksums: _checksums);
      expect(updated, contains('macos-x64.tar.gz"\n      sha256 "$_intel"'));
      expect(updated, contains('macos-arm64.tar.gz"\n      sha256 "$_arm"'));
    });

    void expectError(
      String formula,
      String version,
      Map<String, String> checksums,
      String message,
    ) {
      expect(
        () => updateFormula(formula, version: version, checksums: checksums),
        throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains(message))),
      );
    }

    test('rejects a prerelease version', () {
      expectError(_placeholderFormula, '0.6.0-wip', _checksums, 'is not <major>.<minor>.<patch>');
    });

    test('rejects SHA256SUMS without an archive of the formula', () {
      expectError(_placeholderFormula, '0.6.0', {
        'skills_lint-macos-arm64.tar.gz': _arm,
      }, 'SHA256SUMS has no checksum for skills_lint-macos-x64.tar.gz');
    });

    test('rejects a url without a sha256 line after it', () {
      final String formula = _placeholderFormula.replaceFirst(
        '      sha256 "$_zeros" # PLACEHOLDER\n',
        '',
      );
      expectError(
        formula,
        '0.6.0',
        _checksums,
        'skills_lint-macos-arm64.tar.gz is not followed by a sha256 line',
      );
    });

    test('rejects a formula without a version or without archives', () {
      expectError(
        _placeholderFormula.replaceFirst(RegExp('  version .*\n'), ''),
        '0.6.0',
        _checksums,
        'has 0 version lines',
      );
      expectError(
        'class SkillsLint < Formula\n  version "1.0.0"\nend\n',
        '0.6.0',
        _checksums,
        '0 archive urls',
      );
    });

    test('rejects a url line that it does not read', () {
      expectError(
        _releasedFormula.replaceFirst('macos-arm64.tar.gz"', 'macos-arm64.tar.gz" # Apple silicon'),
        '0.6.1',
        _checksums,
        '1 archive urls and 2 sha256 lines',
      );
    });

    test('rejects a PLACEHOLDER comment that it does not remove', () {
      final String formula = _placeholderFormula.replaceFirst(
        '  livecheck do',
        '  # PLACEHOLDER\n  livecheck do',
      );
      expectError(
        formula,
        '0.6.0',
        _checksums,
        'PLACEHOLDER comment that this command does not remove',
      );
    });
  });

  test(
    'updates Formula/skills_lint.rb with the checksum of each target that Homebrew installs',
    () {
      final String formula = File(p.join(repoRoot, 'Formula', 'skills_lint.rb')).readAsStringSync();
      final Map<String, String> checksums = {};
      final List<ReleaseTarget> targets = homebrewTargets;
      for (final (int index, ReleaseTarget target) in targets.indexed) {
        checksums[archiveName(target.name)] = (index + 1).toRadixString(16).padLeft(64, 'f');
      }
      final String updated = updateFormula(formula, version: '9.8.7', checksums: checksums);
      expect(updated, contains('version "9.8.7"\n'));
      expect(updated, isNot(contains('PLACEHOLDER')));
      for (final MapEntry<String, String> checksum in checksums.entries) {
        expect(updated, contains('/${checksum.key}"\n      sha256 "${checksum.value}"\n'));
      }
    },
  );
}
