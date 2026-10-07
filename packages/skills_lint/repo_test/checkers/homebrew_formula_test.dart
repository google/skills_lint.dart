// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/homebrew_formula.dart';
import '../src/models/convention_violation.dart';

const List<String> _targets = ['macos-arm64', 'macos-x64', 'linux-arm64', 'linux-x64'];
final String _zeros = '0' * 64;
final String _shaA = 'a' * 64;
final String _shaB = 'b' * 64;
final String _shaC = 'c' * 64;
final String _shaD = 'd' * 64;

/// Builds a formula with one block per entry of [blocks], which maps
/// `<os>-<arch>` to the block's `url` target and `sha256` line.
String _formula({
  String version = 'version "1.2.0"',
  String macos = 'depends_on macos: :sonoma',
  Map<String, (String, String)>? blocks,
}) {
  final Map<String, (String, String)> entries =
      blocks ??
      {
        'macos-arm64': ('macos-arm64', 'sha256 "$_shaA"'),
        'macos-x64': ('macos-x64', 'sha256 "$_shaB"'),
        'linux-arm64': ('linux-arm64', 'sha256 "$_shaC"'),
        'linux-x64': ('linux-x64', 'sha256 "$_shaD"'),
      };
  String block(String os) => [
    for (final MapEntry<String, (String, String)> entry in entries.entries)
      if (entry.key.startsWith(os))
        '''
    on_${entry.key.endsWith('arm64') ? 'arm' : 'intel'} do
      url "${expectedArchiveUrl(entry.value.$1)}"
      ${entry.value.$2}
    end''',
  ].join('\n');
  return '''
class SkillsLint < Formula
  $version
  livecheck do
    url :stable
  end
  on_macos do
    $macos
${block('macos')}
  end
  on_linux do
${block('linux')}
  end
  def install
    url "https://example.com/ignored.tar.gz"
  end
end
''';
}

List<String> _archiveProblems(String content, [List<String> targets = _targets]) =>
    _describe(findArchiveViolations('f.rb', parseFormula(content), targets));

List<String> _versionProblems(
  String content, {
  String pubspec = '1.3.0-wip',
  String changelog = '## 1.2.0\n',
}) => _describe(
  findVersionViolations(
    'f.rb',
    parseFormula(content),
    pubspecVersion: pubspec,
    changelog: changelog,
  ),
);

List<String> _describe(List<ConventionViolation> violations) => [
  for (final v in violations) v.describe(),
];

/// Runs the formula checks over small inline formulas, which pins what each
/// one reports independently of `Formula/skills_lint.rb`.
void main() {
  group('formulaTargets', () {
    test('keeps macOS and Linux targets on arm64 and x64, in order', () {
      expect(
        formulaTargets(['linux-x64', 'windows-x64', 'linux-riscv64', 'macos-arm64', 'linux-arm64']),
        ['linux-x64', 'macos-arm64', 'linux-arm64'],
      );
    });
  });

  group('parseFormula', () {
    test('reads the version, each archive and the macOS dependency, and stops at def', () {
      final HomebrewFormula formula = parseFormula(_formula());
      expect(formula.version?.value, '1.2.0');
      expect(formula.archives.keys, _targets);
      expect(formula.archives['linux-arm64']!.sha256s.single.value, _shaC);
      expect(formula.macosMinimum?.value, 'sonoma');
      expect(formula.macosMinimumOnMacosOnly, isTrue);
      expect(formula.unscopedValues, isEmpty);
      expect(formula.hasPlaceholders, isFalse);
    });
  });

  group('findArchiveViolations', () {
    test('reports nothing for one exact url and distinct sha256 per target', () {
      expect(_archiveProblems(_formula()), isEmpty);
    });

    test('reports swapped archives', () {
      final String content = _formula(
        blocks: {
          'macos-arm64': ('macos-x64', 'sha256 "$_shaA"'),
          'macos-x64': ('macos-arm64', 'sha256 "$_shaB"'),
          'linux-arm64': ('linux-arm64', 'sha256 "$_shaC"'),
          'linux-x64': ('linux-x64', 'sha256 "$_shaD"'),
        },
      );
      final String arm = expectedArchiveUrl('macos-arm64');
      final String intel = expectedArchiveUrl('macos-x64');
      expect(_archiveProblems(content), [
        'f.rb:9: the macos-arm64 url is "$intel"; expected "$arm"',
        'f.rb:13: the macos-x64 url is "$arm"; expected "$intel"',
      ]);
    });

    test('reports a missing target and a block for a target that is not released', () {
      final String content = _formula(
        blocks: {
          'macos-arm64': ('macos-arm64', 'sha256 "$_shaA"'),
          'macos-x64': ('macos-x64', 'sha256 "$_shaB"'),
          'linux-x64': ('linux-x64', 'sha256 "$_shaD"'),
        },
      );
      expect(_archiveProblems(content, ['macos-arm64', 'linux-arm64', 'linux-x64']), [
        'f.rb:1: has no block for the release target linux-arm64',
        'f.rb:13: has a block for macos-x64, which is not a release target',
      ]);
    });

    test('reports a repeated sha256 and a block without one', () {
      final String content = _formula(
        blocks: {
          'macos-arm64': ('macos-arm64', 'sha256 "$_shaA"'),
          'macos-x64': ('macos-x64', 'sha256 "$_shaA"'),
          'linux-arm64': ('linux-arm64', '# no sha256'),
          'linux-x64': ('linux-x64', 'sha256 "$_shaD"'),
        },
      );
      expect(_archiveProblems(content), [
        'f.rb:19: the linux-arm64 block has 1 url and 0 sha256 lines; expected one of each',
        'f.rb:14: sha256 $_shaA is also the sha256 of another archive',
      ]);
    });

    test('reports placeholders without the marker, partial placeholders and a real version', () {
      final String content = _formula(
        blocks: {
          'macos-arm64': ('macos-arm64', 'sha256 "$_zeros" $placeholderMarker'),
          'macos-x64': ('macos-x64', 'sha256 "$_zeros"'),
          'linux-arm64': ('linux-arm64', 'sha256 "$_shaC" $placeholderMarker'),
          'linux-x64': ('linux-x64', 'sha256 "$_shaD"'),
        },
      );
      const allOrNone =
          'replace every placeholder in one change: the version and all sha256 values are '
          'placeholders, or none are';
      expect(_archiveProblems(content), [
        'f.rb:14: a sha256 is 64 zeros if and only if its line ends with $placeholderMarker',
        'f.rb:20: a sha256 is 64 zeros if and only if its line ends with $placeholderMarker',
        'f.rb:2: $allOrNone',
      ]);
    });

    test('accepts a formula whose version and sha256 values are all placeholders', () {
      final String content = _formula(
        version: 'version "1.3.0" $placeholderMarker',
        blocks: {
          for (final target in _targets) target: (target, 'sha256 "$_zeros" $placeholderMarker'),
        },
      );
      expect(_archiveProblems(content), isEmpty);
      expect(parseFormula(content).hasPlaceholders, isTrue);
    });

    test('reports a url outside a platform block', () {
      final String content = _formula().replaceFirst('  livecheck do', '  url "x"\n  livecheck do');
      expect(_archiveProblems(content), [
        'f.rb:3: "x" is outside an on_macos/on_linux and on_arm/on_intel block',
      ]);
    });
  });

  group('findVersionViolations', () {
    final String placeholders = _formula(
      version: 'version "1.3.0" $placeholderMarker',
      blocks: {
        for (final target in _targets) target: (target, 'sha256 "$_zeros" $placeholderMarker'),
      },
    );

    test('accepts a released version that the CHANGELOG lists', () {
      expect(_versionProblems(_formula()), isEmpty);
      expect(_versionProblems(_formula(), pubspec: '1.2.0'), isEmpty);
    });

    test('accepts a placeholder version equal to the pubspec version without its suffix', () {
      expect(_versionProblems(placeholders, changelog: ''), isEmpty);
    });

    test('reports a placeholder version that is not the pending release', () {
      expect(_versionProblems(placeholders, pubspec: '1.4.0-wip'), [
        'f.rb:2: placeholder version "1.3.0" must be 1.4.0, the pubspec version 1.4.0-wip without its suffix',
      ]);
    });

    test('reports a release that the CHANGELOG does not list', () {
      expect(_versionProblems(_formula(), changelog: '## 1.2.0-wip\n## 1.2.00\n'), [
        'f.rb:2: version "1.2.0" has no "## 1.2.0" heading in the CHANGELOG, so it is not a release',
      ]);
    });

    test('reports a version newer than the pubspec version', () {
      expect(_versionProblems(_formula(), pubspec: '1.2.0-wip'), [
        'f.rb:2: version "1.2.0" is newer than the pubspec version 1.2.0-wip',
      ]);
    });

    test('reports a prerelease, a version that does not parse, and a missing version', () {
      expect(_versionProblems(_formula(version: 'version "1.2.0-wip"')), [
        'f.rb:2: version "1.2.0-wip" is a prerelease; Homebrew installs releases only',
      ]);
      expect(_versionProblems(_formula(version: 'version "9"')), [
        'f.rb:2: version "9" is not a semantic version',
      ]);
      expect(_versionProblems(_formula(version: '')), ['f.rb:1: has no version']);
    });
  });

  group('findMacosViolations', () {
    List<String> problems(String content, String? minimum) =>
        _describe(findMacosViolations('f.rb', parseFormula(content), minimum));

    test('accepts the symbol for the minimum version inside on_macos', () {
      expect(problems(_formula(), '14.0'), isEmpty);
      expect(problems(_formula(), null), isEmpty);
    });

    test('reports a dependency outside on_macos', () {
      final String content = _formula(
        macos: '',
      ).replaceFirst('  livecheck do', '  depends_on macos: :sonoma\n  livecheck do');
      expect(problems(content, '14.0'), [
        'f.rb:3: depends_on macos: is outside on_macos, so Linux cannot install',
      ]);
    });

    test('reports a symbol for another version, an unknown symbol and no dependency', () {
      expect(problems(_formula(), '15.0'), [
        'f.rb:7: :sonoma is macOS 14.0, but the executables need macOS 15.0',
      ]);
      expect(problems(_formula(), '14.5'), [
        'f.rb:7: :sonoma is macOS 14.0, but the executables need macOS 14.5',
      ]);
      expect(problems(_formula(macos: 'depends_on macos: :big_sur'), '14.0'), [
        'f.rb:7: :big_sur is not in macosSymbolMajors',
      ]);
      expect(problems(_formula(macos: ''), '14.0'), [
        'f.rb:1: has no depends_on macos: inside on_macos',
      ]);
    });
  });
}
