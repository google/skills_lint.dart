// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:test/test.dart';

import '../src/homebrew/archive_violations.dart';
import '../src/homebrew/formula_value.dart';
import '../src/homebrew/homebrew_formula.dart';
import '../src/homebrew/macos_violations.dart';
import '../src/homebrew/version_violations.dart';
import '../src/models/convention_violation.dart';

/// The targets of the test formulas. The checks take the targets as an
/// argument, so these don't need to match `releaseTargets`.
const List<String> _targets = ['macos-arm64', 'linux-arm64', 'linux-x64'];

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

List<ConventionViolation> _archiveProblems(String content, [List<String> targets = _targets]) =>
    findArchiveViolations('f.rb', HomebrewFormula.parse(content), targets);

List<ConventionViolation> _versionProblems(
  String content, {
  String pubspec = '1.3.0-wip',
  String changelog = '## 1.2.0\n',
}) => findVersionViolations(
  'f.rb',
  HomebrewFormula.parse(content),
  pubspecVersion: pubspec,
  changelog: changelog,
);

/// Matches a violation on [line] whose problem names [subject], so that
/// rewording a message doesn't break the tests.
Matcher _violation(int line, String subject) => isA<ConventionViolation>()
    .having((ConventionViolation v) => v.line, 'line', line)
    .having((ConventionViolation v) => v.problem, 'problem', contains(subject));

/// Runs the formula checks over small inline formulas, which pins what each
/// one reports independently of `Formula/skills_lint.rb`.
void main() {
  group('HomebrewFormula.parse', () {
    test('reads the version, each archive and the macOS dependency, and stops at def', () {
      final formula = HomebrewFormula.parse(_formula());
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
      expect(
        _archiveProblems(content),
        unorderedEquals([
          _violation(_urlLine(content, second), expectedArchiveUrl(second)),
          _violation(_urlLine(content, first), expectedArchiveUrl(first)),
        ]),
      );
    });

    test('reports a missing target and a block for a target that is not released', () {
      final String missing = _targets.last;
      final String unreleased = _targets[1];
      final String content = _formula(blocks: _validBlocks()..remove(missing));
      final List<String> released = [..._targets]..remove(unreleased);
      expect(_archiveProblems(content, released), [
        _violation(missingStatementLine, missing),
        _violation(_urlLine(content, unreleased), unreleased),
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
      expect(
        _archiveProblems(content),
        unorderedEquals([
          _violation(_urlLine(content, withoutSha256), withoutSha256),
          _violation(repeatedLine, _sha(0)),
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
      expect(
        _archiveProblems(content),
        unorderedEquals([
          _violation(_urlLine(content, unmarked) + 1, placeholderMarker),
          _violation(_urlLine(content, markedReal) + 1, placeholderMarker),
          _violation(2, 'placeholder'),
        ]),
      );
    });

    test('accepts a formula whose version and sha256 values are all placeholders', () {
      final String content = _formula(
        version: 'version "1.3.0" $placeholderMarker',
        blocks: _placeholderBlocks(),
      );
      expect(_archiveProblems(content), isEmpty);
      expect(HomebrewFormula.parse(content).hasPlaceholders, isTrue);
    });

    test('reports a placeholder version with real sha256 values, and the reverse', () {
      final String placeholderVersion = _formula(version: 'version "1.3.0" $placeholderMarker');
      final String placeholderSha256s = _formula(blocks: _placeholderBlocks());
      expect(_archiveProblems(placeholderVersion), [_violation(2, 'placeholder')]);
      expect(_archiveProblems(placeholderSha256s), [_violation(2, 'placeholder')]);
    });

    test('reports a url outside a platform block', () {
      final String content = _formula().replaceFirst('  livecheck do', '  url "x"\n  livecheck do');
      expect(_archiveProblems(content), [_violation(3, '"x"')]);
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
      expect(_versionProblems(placeholders(), pubspec: '1.4.0-wip'), [_violation(2, '1.4.0')]);
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
        _violation(2, 'CHANGELOG'),
      ]);
    });

    test('reports a version newer than the pubspec version', () {
      expect(_versionProblems(_formula(), pubspec: '1.2.0-wip'), [_violation(2, '1.2.0-wip')]);
    });

    test('reports a prerelease, a version that does not parse, and a missing version', () {
      expect(_versionProblems(_formula(version: 'version "1.2.0-wip"')), [
        _violation(2, 'prerelease'),
      ]);
      expect(_versionProblems(_formula(version: 'version "9"')), [
        _violation(2, 'semantic version'),
      ]);
      expect(_versionProblems(_formula(version: '')), [
        _violation(missingStatementLine, 'version'),
      ]);
    });
  });

  group('findMacosViolations', () {
    List<ConventionViolation> problems(String content, String? minimum) =>
        findMacosViolations('f.rb', HomebrewFormula.parse(content), minimum);

    test('accepts the symbol for the minimum version inside on_macos', () {
      expect(problems(_formula(), '14.0'), isEmpty);
      expect(problems(_formula(), null), isEmpty);
    });

    test('reports a dependency outside on_macos', () {
      final String content = _formula(
        macos: '',
      ).replaceFirst('  livecheck do', '  depends_on macos: :sonoma\n  livecheck do');
      expect(problems(content, '14.0'), [_violation(3, 'on_macos')]);
    });

    test('reports a symbol for another version, an unknown symbol and no dependency', () {
      expect(problems(_formula(), '15.0'), [_violation(7, '15.0')]);
      expect(problems(_formula(), '14.5'), [_violation(7, '14.5')]);
      expect(problems(_formula(macos: 'depends_on macos: :big_sur'), '14.0'), [
        _violation(7, 'big_sur'),
      ]);
      expect(problems(_formula(macos: ''), '14.0'), [
        _violation(missingStatementLine, 'depends_on macos:'),
      ]);
    });
  });
}
