// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/homebrew_formula.dart';
import 'package:skills_lint_release/src/homebrew_formula_check.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:test/test.dart';

/// A template with only the placeholders, so the tests don't depend on the
/// real template's Ruby.
const String _template = 'version "{{version}}"\n{{platforms}}\nend\n';

const String _url =
    'https://github.com/google/skills_lint.dart/releases/download/skills_lint-v#{version}';

const _macosArm = ReleaseTarget(os: TargetOs.macos, arch: TargetArch.arm64, runner: 'm');
const _linuxIntel = ReleaseTarget(os: TargetOs.linux, arch: TargetArch.x64, runner: 'l');
const _linuxArm = ReleaseTarget(os: TargetOs.linux, arch: TargetArch.arm64, runner: 'l');
const _windows = ReleaseTarget(os: TargetOs.windows, arch: TargetArch.x64, runner: 'w');
const _riscv = ReleaseTarget(os: TargetOs.linux, arch: TargetArch.riscv64, runner: 'r');

/// A different checksum for the archive of each of [targets]: `111…`, then
/// `222…`, and so on. A formula that puts one archive's checksum in another
/// archive's block doesn't match.
Map<String, String> _checksums(List<ReleaseTarget> targets) => {
  for (final (int i, ReleaseTarget target) in targets.indexed)
    archiveName(target.name): '${i + 1}' * 64,
};

String _render(
  String version, {
  required List<ReleaseTarget> targets,
  Map<String, String>? checksums,
}) => renderFormula(
  _template,
  FormulaValues(version: version, checksums: checksums),
  targets: targets,
);

/// A formula for [version] with a checksum for each of [releaseTargets].
String _release(String version) =>
    _render(version, targets: releaseTargets, checksums: _checksums(releaseTargets));

/// A formula for [version] with placeholder checksums.
String _placeholders(String version) => _render(version, targets: releaseTargets);

List<String> _problems(String formula, {required String pubspec, required String changelog}) =>
    formulaProblems(formula, template: _template, pubspecVersion: pubspec, changelog: changelog);

void main() {
  group('renderFormula', () {
    test('nests an arch block in an os block for each target that Homebrew installs', () {
      final List<ReleaseTarget> targets = [_linuxIntel, _linuxArm, _windows, _riscv];
      expect(_render('1.2.0', targets: targets, checksums: _checksums(targets)), '''
version "1.2.0"
  on_linux do
    on_intel do
      url "$_url/skills_lint-linux-x64.tar.gz"
      sha256 "${'1' * 64}"
    end
    on_arm do
      url "$_url/skills_lint-linux-arm64.tar.gz"
      sha256 "${'2' * 64}"
    end
  end
end
''');
    });

    test('puts depends_on macos: inside on_macos only', () {
      final List<ReleaseTarget> targets = [_macosArm, _linuxIntel];
      final String formula = _render('1.2.0', targets: targets, checksums: _checksums(targets));
      expect(formula, contains('  on_macos do\n    depends_on macos: :'));
      expect('depends_on'.allMatches(formula), hasLength(1));
    });

    test('adds a block for a new target and changes nothing else', () {
      final List<ReleaseTarget> before = [_macosArm, _linuxIntel];
      final List<ReleaseTarget> after = [...before, _linuxArm];
      final Map<String, String> checksums = _checksums(after);
      final String added = _render('1.2.0', targets: after, checksums: checksums);
      expect(
        added.replaceFirst('''
    on_arm do
      url "$_url/skills_lint-linux-arm64.tar.gz"
      sha256 "${checksums['skills_lint-linux-arm64.tar.gz']}"
    end
''', ''),
        _render('1.2.0', targets: before, checksums: checksums),
      );
    });

    test('writes placeholder checksums when there are no checksums', () {
      final String formula = _render('1.3.0', targets: [_macosArm, _linuxIntel]);
      expect(RegExp('sha256 "$placeholderSha256" # PLACEHOLDER').allMatches(formula), hasLength(2));
    });

    test('rejects checksums that lack an archive', () {
      expect(
        () =>
            _render('1.2.0', targets: [_macosArm, _linuxIntel], checksums: _checksums([_macosArm])),
        throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains('linux-x64'))),
      );
    });

    test('rejects a template without a placeholder', () {
      expect(
        () => renderFormula('{{version}}', const FormulaValues(version: '1.2.0')),
        throwsA(isA<ReleaseException>()),
      );
    });
  });

  group('releaseFormula', () {
    test('takes the checksum of each archive from SHA256SUMS', () {
      final Map<String, String> checksums = _checksums(releaseTargets);
      final String sums = [
        for (final String archive in checksums.keys) '${checksums[archive]}  $archive',
        '${'b' * 64}  pubspec.lock',
      ].join('\n');
      final String formula = releaseFormula(_template, version: '1.2.0+1', sha256Sums: sums);
      expect(formula, startsWith('version "1.2.0+1"\n'));
      expect(readFormula(formula).checksums, checksums);
    });

    test('rejects a version that Homebrew cannot install', () {
      for (final version in ['1.2.0-wip', 'abc', '1.2', '1.2.0+hotfix']) {
        expect(
          () => releaseFormula(_template, version: version, sha256Sums: ''),
          throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains(version))),
          reason: version,
        );
      }
    });
  });

  group('readFormula', () {
    test('reads back the version and checksums that renderFormula wrote', () {
      final FormulaValues release = readFormula(_release('1.2.0'));
      expect(release.version, '1.2.0');
      expect(release.checksums, _checksums(releaseTargets));
    });

    test('reads placeholder checksums as no checksums', () {
      final FormulaValues placeholders = readFormula(_placeholders('1.3.0'));
      expect(placeholders.version, '1.3.0');
      expect(placeholders.checksums, isNull);
    });
  });

  group('formulaProblems', () {
    test('accepts a released version older than the pubspec version', () {
      expect(_problems(_release('1.2.0'), pubspec: '1.3.0-wip', changelog: '## 1.2.0\n'), isEmpty);
    });

    test('accepts a released version equal to the pubspec version', () {
      // The state right after a release, when the formula bump lands.
      expect(_problems(_release('1.2.0'), pubspec: '1.2.0', changelog: '## 1.2.0\n'), isEmpty);
    });

    test('accepts placeholders for the pubspec version without -wip', () {
      expect(_problems(_placeholders('1.3.0'), pubspec: '1.3.0-wip', changelog: ''), isEmpty);
    });

    test('rejects placeholders for any other version', () {
      expect(_problems(_placeholders('1.2.5'), pubspec: '1.3.0-wip', changelog: ''), [
        'placeholder version "1.2.5" must be 1.3.0, the pubspec version without -wip',
      ]);
    });

    test('rejects a version that Homebrew cannot install', () {
      expect(_problems(_release('1.2.0-dev.1'), pubspec: '1.2.0-dev.1', changelog: ''), [
        'version "1.2.0-dev.1" is not a release that Homebrew can install',
      ]);
    });

    test('rejects a released version that has no CHANGELOG heading', () {
      expect(_problems(_release('1.2.0'), pubspec: '1.3.0-wip', changelog: '## 1.1.0\n'), [
        'version "1.2.0" has no "## 1.2.0" heading in the CHANGELOG',
      ]);
    });

    test('rejects a released version newer than the pubspec version', () {
      expect(_problems(_release('1.2.0'), pubspec: '1.2.0-wip', changelog: '## 1.2.0\n'), [
        'version "1.2.0" is newer than the pubspec version 1.2.0-wip',
      ]);
    });

    test('rejects a change outside the version and checksums', () {
      final String edited = _release('1.2.0').replaceFirst('on_intel', 'on_arm');
      expect(_problems(edited, pubspec: '1.3.0-wip', changelog: '## 1.2.0\n'), [
        'it is not what the template gives',
      ]);
    });
  });
}
