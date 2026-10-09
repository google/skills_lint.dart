// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/homebrew_formula.dart';
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

const List<ReleaseTarget> _targets = [_macosArm, _linuxIntel, _windows, _riscv];

final String _sha = 'a' * 64;

/// A checksum for the archive of each of [targets].
Map<String, String> _checksums(List<ReleaseTarget> targets) => {
  for (final ReleaseTarget target in targets) archiveName(target.name): _sha,
};

String _render(String version, {Map<String, String>? checksums, List<ReleaseTarget>? targets}) =>
    renderFormula(
      _template,
      FormulaValues(version: version, checksums: checksums),
      targets: targets ?? _targets,
    );

List<String> _problems(
  String formula, {
  String pubspec = '1.3.0-wip',
  String changelog = '## 1.2.0\n',
}) => formulaProblems(
  formula,
  template: _template,
  pubspecVersion: pubspec,
  changelog: changelog,
  targets: _targets,
);

void main() {
  group('renderFormula', () {
    test('nests an arch block in an os block for each target that Homebrew can install', () {
      expect(_render('1.2.0', checksums: _checksums(_targets)), '''
version "1.2.0"
  on_macos do
    depends_on macos: :sonoma

    on_arm do
      url "$_url/skills_lint-macos-arm64.tar.gz"
      sha256 "$_sha"
    end
  end

  on_linux do
    on_intel do
      url "$_url/skills_lint-linux-x64.tar.gz"
      sha256 "$_sha"
    end
  end
end
''');
    });

    test('adds a block for a new target and changes nothing else', () {
      final List<ReleaseTarget> more = [..._targets, _linuxArm];
      final String before = _render('1.2.0', checksums: _checksums(more));
      final String after = _render('1.2.0', checksums: _checksums(more), targets: more);
      expect(after, contains('skills_lint-linux-arm64.tar.gz'));
      expect(
        after.replaceFirst('''
    on_arm do
      url "$_url/skills_lint-linux-arm64.tar.gz"
      sha256 "$_sha"
    end
''', ''),
        before,
      );
    });

    test('writes placeholder checksums when there are no checksums', () {
      final String formula = _render('1.3.0');
      expect(RegExp('sha256 "$placeholderSha256" # PLACEHOLDER').allMatches(formula), hasLength(2));
    });

    test('rejects checksums that lack an archive, and a template without a placeholder', () {
      expect(
        () => _render('1.2.0', checksums: _checksums([_macosArm])),
        throwsA(isA<ReleaseException>().having((e) => e.message, 'message', contains('linux-x64'))),
      );
      expect(
        () => renderFormula('{{version}}', const FormulaValues(version: '1.2.0')),
        throwsA(isA<ReleaseException>()),
      );
    });
  });

  group('readFormula', () {
    test('reads back the version and checksums that renderFormula wrote', () {
      final Map<String, String> checksums = _checksums(homebrewTargets(_targets));
      final FormulaValues release = readFormula(_render('1.2.0', checksums: checksums));
      expect(release.version, '1.2.0');
      expect(release.checksums, checksums);
      final FormulaValues placeholders = readFormula(_render('1.3.0'));
      expect(placeholders.version, '1.3.0');
      expect(placeholders.checksums, isNull);
    });
  });

  group('formulaProblems', () {
    test('accepts a rendered release, and a rendered placeholder for the pending release', () {
      expect(_problems(_render('1.2.0', checksums: _checksums(_targets))), isEmpty);
      expect(_problems(_render('1.3.0')), isEmpty);
    });

    test('reports a hand edit by its line', () {
      final String edited = _render(
        '1.2.0',
        checksums: _checksums(_targets),
      ).replaceFirst('on_intel', 'on_arm');
      expect(_problems(edited), [contains('line 12')]);
    });

    test('reports a version that breaks the release rules', () {
      final Map<String, String> checksums = _checksums(_targets);
      expect(_problems(_render('1.2.0-dev.1', checksums: checksums)), [contains('1.2.0-dev.1')]);
      expect(_problems(_render('1.2.5')), [contains('1.3.0')]);
      expect(_problems(_render('1.2.0', checksums: checksums), changelog: ''), [
        contains('CHANGELOG'),
      ]);
      expect(_problems(_render('1.2.0', checksums: checksums), pubspec: '1.2.0-wip'), [
        contains('1.2.0-wip'),
      ]);
    });
  });
}
