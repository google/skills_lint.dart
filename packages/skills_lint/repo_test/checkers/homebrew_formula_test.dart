// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:test/test.dart';

import '../src/homebrew_formula.dart';
import '../src/homebrew_targets.dart';
import '../src/models/convention_violation.dart';

/// The targets that Homebrew installs, from `releaseTargets`.
late final List<String> _targets;

/// The violation for a formula whose version and sha256 values are not all
/// placeholders or all real.
const String _allOrNone =
    'replace every placeholder in one change: the version and all sha256 values are '
    'placeholders, or none are';

/// A distinct, well-formed sha256 for the target at [index].
String _sha(int index) => (index + 1).toRadixString(16).padLeft(64, 'f');

/// Each target's block, with its own url and a distinct sha256.
Map<String, (String, String)> _validBlocks() => {
  for (final (int index, String target) in _targets.indexed)
    target: (target, 'sha256 "${_sha(index)}"'),
};

/// Each target's block, with its own url and a placeholder sha256.
Map<String, (String, String)> _placeholderBlocks() => {
  for (final String target in _targets)
    target: (target, 'sha256 "$placeholderSha256" $placeholderMarker'),
};

/// Builds a formula with one block per entry of [blocks], which maps the
/// block's `<os>-<arch>` to the target in its `url` and its `sha256` line.
///
/// The first seven lines are fixed: `version` is on line 2 and
/// `depends_on macos:` on line 7.
String _formula({
  String version = 'version "1.2.0"',
  String macos = 'depends_on macos: :sonoma',
  Map<String, (String, String)>? blocks,
}) {
  final Map<String, (String, String)> entries = blocks ?? _validBlocks();
  String osBlocks(String os) {
    final List<String> lines = [];
    for (final MapEntry<String, (String, String)> entry in entries.entries) {
      if (!entry.key.startsWith('$os-')) {
        continue;
      }
      final archBlock = entry.key.endsWith('-arm64') ? 'on_arm' : 'on_intel';
      final (String urlTarget, String sha256Line) = entry.value;
      lines.add('''
    $archBlock do
      url "${expectedArchiveUrl(urlTarget)}"
      $sha256Line
    end''');
    }
    return lines.join('\n');
  }

  return '''
class SkillsLint < Formula
  $version
  livecheck do
    url :stable
  end
  on_macos do
    $macos
${osBlocks('macos')}
  end
  on_linux do
${osBlocks('linux')}
  end
  def install
    url "https://example.com/ignored.tar.gz"
  end
end
''';
}

/// The 1-based line of the `url` that names the archive of [target].
int _urlLine(String content, String target) {
  final String url = expectedArchiveUrl(target);
  final List<String> lines = content.split('\n');
  final int index = lines.indexWhere((String line) => line.contains(url));
  expect(index, isNot(-1), reason: 'No url for $target in the formula.');
  return index + 1;
}

List<String> _archiveProblems(String content, [List<String>? targets]) =>
    _describe(findArchiveViolations('f.rb', parseFormula(content), targets ?? _targets));

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
/// one reports independently of `Formula/skills_lint.rb`. The formulas have
/// a block for each target that Homebrew installs.
void main() {
  setUpAll(() async {
    _targets = await readHomebrewTargets();
    expect(_targets.length, greaterThanOrEqualTo(3), reason: 'The tests below edit three blocks.');
  });

  group('parseFormula', () {
    test('reads the version, each archive and the macOS dependency, and stops at def', () {
      final HomebrewFormula formula = parseFormula(_formula());
      expect(formula.version?.value, '1.2.0');
      expect(formula.archives.keys, unorderedEquals(_targets));
      expect(formula.archives[_targets.last]!.sha256s.single.value, _sha(_targets.length - 1));
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
      final [String first, String second, ...] = _targets;
      final Map<String, (String, String)> blocks = _validBlocks();
      blocks[first] = (second, blocks[first]!.$2);
      blocks[second] = (first, blocks[second]!.$2);
      final String content = _formula(blocks: blocks);
      final String firstUrl = expectedArchiveUrl(first);
      final String secondUrl = expectedArchiveUrl(second);
      expect(
        _archiveProblems(content),
        unorderedEquals([
          'f.rb:${_urlLine(content, second)}: the $first url is "$secondUrl"; expected "$firstUrl"',
          'f.rb:${_urlLine(content, first)}: the $second url is "$firstUrl"; expected "$secondUrl"',
        ]),
      );
    });

    test('reports a missing target and a block for a target that is not released', () {
      final String missing = _targets.last;
      final String unreleased = _targets[1];
      final String content = _formula(blocks: _validBlocks()..remove(missing));
      final List<String> released = [..._targets]..remove(unreleased);
      expect(_archiveProblems(content, released), [
        'f.rb:1: has no block for the release target $missing',
        'f.rb:${_urlLine(content, unreleased)}: has a block for $unreleased, which is not a release target',
      ]);
    });

    test('reports a repeated sha256 and a block without one', () {
      final [String first, String repeating, String withoutSha256, ...] = _targets;
      final Map<String, (String, String)> blocks = _validBlocks();
      blocks[repeating] = (repeating, blocks[first]!.$2);
      blocks[withoutSha256] = (withoutSha256, '# no sha256');
      final String content = _formula(blocks: blocks);
      // The check reports the copy that comes second in the file.
      final int repeatedLine = max(_urlLine(content, first), _urlLine(content, repeating)) + 1;
      final int blockLine = _urlLine(content, withoutSha256);
      expect(
        _archiveProblems(content),
        unorderedEquals([
          'f.rb:$blockLine: the $withoutSha256 block has 1 url and 0 sha256 lines; expected one of each',
          'f.rb:$repeatedLine: sha256 ${_sha(0)} is also the sha256 of another archive',
        ]),
      );
    });

    test('reports placeholders without the marker, partial placeholders and a real version', () {
      final [String marked, String unmarked, String markedReal, ...] = _targets;
      final Map<String, (String, String)> blocks = _validBlocks();
      blocks[marked] = (marked, 'sha256 "$placeholderSha256" $placeholderMarker');
      blocks[unmarked] = (unmarked, 'sha256 "$placeholderSha256"');
      blocks[markedReal] = (markedReal, 'sha256 "${_sha(2)}" $placeholderMarker');
      final String content = _formula(blocks: blocks);
      const markerRule = 'a sha256 is 64 zeros if and only if its line has $placeholderMarker';
      final List<String> problems = _archiveProblems(content);
      expect(problems.last, 'f.rb:2: $_allOrNone');
      expect(
        problems.take(problems.length - 1),
        unorderedEquals([
          'f.rb:${_urlLine(content, unmarked) + 1}: $markerRule',
          'f.rb:${_urlLine(content, markedReal) + 1}: $markerRule',
        ]),
      );
    });

    test('accepts a formula whose version and sha256 values are all placeholders', () {
      final String content = _formula(
        version: 'version "1.3.0" $placeholderMarker',
        blocks: _placeholderBlocks(),
      );
      expect(_archiveProblems(content), isEmpty);
      expect(parseFormula(content).hasPlaceholders, isTrue);
    });

    test('reports a placeholder version with real sha256 values, and the reverse', () {
      final String placeholderVersion = _formula(version: 'version "1.3.0" $placeholderMarker');
      final String placeholderSha256s = _formula(blocks: _placeholderBlocks());
      expect(_archiveProblems(placeholderVersion), ['f.rb:2: $_allOrNone']);
      expect(_archiveProblems(placeholderSha256s), ['f.rb:2: $_allOrNone']);
    });

    test('reports a url outside a platform block', () {
      final String content = _formula().replaceFirst('  livecheck do', '  url "x"\n  livecheck do');
      expect(_archiveProblems(content), [
        'f.rb:3: "x" is outside an on_macos/on_linux and on_arm/on_intel block',
      ]);
    });
  });

  group('findVersionViolations', () {
    String placeholders() =>
        _formula(version: 'version "1.3.0" $placeholderMarker', blocks: _placeholderBlocks());

    test('accepts a released version that the CHANGELOG lists', () {
      expect(_versionProblems(_formula()), isEmpty);
      expect(_versionProblems(_formula(), pubspec: '1.2.0'), isEmpty);
    });

    test('accepts a placeholder version equal to the pubspec version without -wip', () {
      expect(_versionProblems(placeholders(), changelog: ''), isEmpty);
    });

    test('reports a placeholder version that is not the pending release', () {
      expect(_versionProblems(placeholders(), pubspec: '1.4.0-wip'), [
        'f.rb:2: placeholder version "1.3.0" must be 1.4.0, the pubspec version 1.4.0-wip without -wip',
      ]);
      expect(_versionProblems(placeholders(), pubspec: '1.3.1-wip'), [
        'f.rb:2: placeholder version "1.3.0" must be 1.3.1, the pubspec version 1.3.1-wip without -wip',
      ]);
    });

    test('accepts a version with build metadata, as a placeholder and as a release', () {
      final String placeholder = _formula(
        version: 'version "1.3.0+1" $placeholderMarker',
        blocks: _placeholderBlocks(),
      );
      final String released = _formula(version: 'version "1.2.0+1"');
      expect(_versionProblems(placeholder, pubspec: '1.3.0+1-wip', changelog: ''), isEmpty);
      expect(_versionProblems(released, changelog: '## 1.2.0+1\n'), isEmpty);
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
