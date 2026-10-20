// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/checksums.dart';
import 'package:skills_lint_release/src/draft_release.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:skills_lint_release/src/release_info.dart';
import 'package:test/test.dart';

const String _repository = 'google/skills_lint.dart';
const String _commit = '0123456789abcdef0123456789abcdef01234567';
const String _buildRun = 'https://github.com/google/skills_lint.dart/actions/runs/1/attempts/1';

/// The output of `gh release view --json isDraft,isPrerelease` for a draft.
String _releaseJson({required bool prerelease, bool draft = true}) =>
    jsonEncode({'isDraft': draft, 'isPrerelease': prerelease});

/// The output of `gh attestation verify --format json` for one attestation
/// signed by [run].
String _attestation(String run) => jsonEncode([
  {
    'verificationResult': {
      'signature': {
        'certificate': {'runInvocationURI': run},
      },
    },
  },
]);

/// A fake `gh` that records each call.
///
/// Answers each `gh attestation verify` with `answer` for the file it names.
final class _FakeGh {
  _FakeGh({ProcessResult Function(String name)? answer})
    : _answer = answer ?? ((_) => ProcessResult(0, 0, _attestation(_buildRun), ''));

  final ProcessResult Function(String name) _answer;

  final List<List<String>> calls = [];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    expect(executable, 'gh');
    calls.add(arguments);
    return _answer(p.basename(arguments[2]));
  }
}

/// Writes the assets that the build makes to [assets], with their SHA256SUMS.
///
/// Each file holds its own name, so no two have the same checksum.
void _writeBuild(Directory assets, {required bool homebrew, String version = '0.6.0'}) {
  final List<String> listed = [
    for (final ReleaseTarget target in releaseTargets) archiveName(target.name),
    lockfileAsset,
  ];
  for (final String name in [...listed, installScriptAsset]) {
    File(p.join(assets.path, name)).writeAsStringSync(name);
  }
  if (homebrew) {
    File(p.join(assets.path, formulaAsset)).writeAsStringSync(_formula(version));
  }
  File(p.join(assets.path, sha256SumsName)).writeAsStringSync(
    [for (final name in listed) '${fileSha256(File(p.join(assets.path, name)))}  $name\n'].join(),
  );
}

/// A formula that installs [version], in the form that `readFormula` reads.
String _formula(String version) =>
    'version "$version"\n'
    'url "https://example.com/${archiveName(releaseTargets.first.name)}"\n'
    'sha256 "${'0' * 64}"\n';

/// Deletes the asset [name] from [assets] and its line from SHA256SUMS.
void _removeAsset(Directory assets, String name) {
  final sums = File(p.join(assets.path, sha256SumsName));
  sums.writeAsStringSync(
    [
      for (final line in sums.readAsLinesSync())
        if (!line.endsWith('  $name')) '$line\n',
    ].join(),
  );
  File(p.join(assets.path, name)).deleteSync();
}

/// Calls [verifyDraft] on [assets] for a run on a tag.
///
/// Uses [_FakeGh] unless [gh] is given. The pubspec version is the tag's
/// unless [pubspecVersion] is given.
Future<VerifiedDraft> _verify(
  Directory assets, {
  required String tag,
  required String releaseJson,
  _FakeGh? gh,
  String refType = 'tag',
  String? pubspecVersion,
}) => verifyDraft(
  refType: refType,
  tag: tag,
  pubspecVersion: pubspecVersion ?? tag.replaceFirst(tagPrefix, ''),
  repository: _repository,
  commit: _commit,
  releaseJson: releaseJson,
  assets: assets,
  runProcess: (gh ?? _FakeGh()).call,
);

/// Expects [verify] to throw a [ReleaseException] whose message contains
/// every one of [parts].
Future<void> _expectProblems(Future<VerifiedDraft> verify, List<String> parts) => expectLater(
  verify,
  throwsA(
    isA<ReleaseException>().having((e) => e.message, 'message', allOf([...parts.map(contains)])),
  ),
);

void main() {
  late Directory assets;

  setUp(() {
    assets = Directory.systemTemp.createTempSync('draft_release_test.');
  });

  tearDown(() {
    assets.deleteSync(recursive: true);
  });

  test('a release draft that the build made gives its version, formula and build runs', () async {
    _writeBuild(assets, homebrew: true);
    final VerifiedDraft draft = await _verify(
      assets,
      tag: '${tagPrefix}0.6.0',
      releaseJson: _releaseJson(prerelease: false),
    );
    expect(draft.version, '0.6.0');
    expect(draft.homebrew, isTrue);
    expect(draft.buildRuns, [_buildRun]);
    expect(draft.outputLines, 'version=0.6.0\nhomebrew=true\n');
    expect(draft.summary, contains('- Version: 0.6.0\n'));
    expect(draft.summary, contains('- Build run: $_buildRun\n'));
  });

  test('every asset is checked against an attestation from the build of the commit', () async {
    _writeBuild(assets, homebrew: true);
    final gh = _FakeGh();
    await _verify(
      assets,
      tag: '${tagPrefix}0.6.0',
      releaseJson: _releaseJson(prerelease: false),
      gh: gh,
    );
    const List<String> flags = [
      '--repo',
      _repository,
      '--signer-workflow',
      '$_repository/$buildWorkflowPath',
      '--source-ref',
      'refs/heads/$releaseBranch',
      '--source-digest',
      _commit,
      '--format',
      'json',
    ];
    expect(
      gh.calls,
      unorderedEquals([
        for (final FileSystemEntity file in assets.listSync())
          ['attestation', 'verify', file.path, ...flags],
      ]),
    );
  });

  test('a prerelease draft has no formula', () async {
    _writeBuild(assets, homebrew: false);
    final VerifiedDraft draft = await _verify(
      assets,
      tag: '${tagPrefix}1.0.0-dev.1',
      releaseJson: _releaseJson(prerelease: true),
    );
    expect(draft.homebrew, isFalse);
    expect(draft.outputLines, 'version=1.0.0-dev.1\nhomebrew=false\n');
  });

  test('a release draft without the formula fails and names it', () async {
    _writeBuild(assets, homebrew: false);
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
      ['$formulaAsset is missing', 'delete the draft'],
    );
  });

  test('a prerelease draft with a formula fails and names it', () async {
    _writeBuild(assets, homebrew: true);
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}1.0.0-dev.1', releaseJson: _releaseJson(prerelease: true)),
      ['$formulaAsset is not an asset of the build'],
    );
  });

  test('a file that the build did not make fails and is named', () async {
    _writeBuild(assets, homebrew: true);
    File(p.join(assets.path, 'extra.txt')).writeAsStringSync('extra');
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
      ['extra.txt is not an asset of the build'],
    );
  });

  test('a changed file fails and is named, and the unchanged ones are not', () async {
    _writeBuild(assets, homebrew: true);
    final String changed = archiveName(releaseTargets.first.name);
    File(p.join(assets.path, changed)).writeAsStringSync('changed');
    await expectLater(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
      throwsA(
        isA<ReleaseException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('$changed does not match its checksum'),
            isNot(contains('$lockfileAsset does not match')),
          ),
        ),
      ),
    );
  });

  test(
    'a SHA256SUMS that leaves out a target archive or pubspec.lock fails and names it',
    () async {
      for (final String name in [archiveName(releaseTargets.last.name), lockfileAsset]) {
        _writeBuild(assets, homebrew: true);
        _removeAsset(assets, name);
        await _expectProblems(
          _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
          ['$sha256SumsName does not list $name'],
        );
      }
    },
  );

  test('a missing or unreadable SHA256SUMS fails', () async {
    _writeBuild(assets, homebrew: true);
    final sums = File(p.join(assets.path, sha256SumsName))..writeAsStringSync('not a checksum\n');
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
      ['not a checksum'],
    );
    sums.deleteSync();
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
      ['$sha256SumsName is missing'],
    );
  });

  test('an asset without an attestation from the build fails and is the only one named', () async {
    _writeBuild(assets, homebrew: true);
    final gh = _FakeGh(
      answer: (name) => name == lockfileAsset
          ? ProcessResult(0, 1, '', 'no matching attestations')
          : ProcessResult(0, 0, _attestation(_buildRun), ''),
    );
    await expectLater(
      _verify(
        assets,
        tag: '${tagPrefix}0.6.0',
        releaseJson: _releaseJson(prerelease: false),
        gh: gh,
      ),
      throwsA(
        isA<ReleaseException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('$lockfileAsset has no attestation from the build of $_commit'),
            contains('no matching attestations'),
            isNot(contains('$installScriptAsset has no attestation')),
          ),
        ),
      ),
    );
  });

  test('attestation output that is not the expected JSON fails', () async {
    _writeBuild(assets, homebrew: true);
    for (final stdout in ['not json', '[]', '[{"verificationResult": {}}]']) {
      final gh = _FakeGh(answer: (_) => ProcessResult(0, 0, stdout, ''));
      await _expectProblems(
        _verify(
          assets,
          tag: '${tagPrefix}0.6.0',
          releaseJson: _releaseJson(prerelease: false),
          gh: gh,
        ),
        ["can't read"],
      );
    }
  });

  test('the build runs of all attestations are listed once each, sorted', () async {
    _writeBuild(assets, homebrew: true);
    // The archives are attested before pubspec.lock, so their run comes
    // first unless the runs are sorted.
    const rerun = 'https://github.com/google/skills_lint.dart/actions/runs/1/attempts/2';
    final gh = _FakeGh(
      answer: (name) =>
          ProcessResult(0, 0, _attestation(name == lockfileAsset ? _buildRun : rerun), ''),
    );
    final VerifiedDraft draft = await _verify(
      assets,
      tag: '${tagPrefix}0.6.0',
      releaseJson: _releaseJson(prerelease: false),
      gh: gh,
    );
    expect(draft.buildRuns, [_buildRun, rerun]);
  });

  test('a run that is not on a release tag fails before reading the draft', () async {
    final gh = _FakeGh();
    for (final (refType, tag) in [
      ('branch', 'main'),
      ('tag', 'v0.6.0'),
      ('tag', tagPrefix),
      ('branch', '${tagPrefix}0.6.0'),
    ]) {
      await _expectProblems(
        _verify(
          assets,
          refType: refType,
          tag: tag,
          releaseJson: _releaseJson(prerelease: false),
          gh: gh,
        ),
        ['Run this workflow on a $tagPrefix<version> tag'],
      );
    }
    expect(gh.calls, isEmpty);
  });

  test('a tag whose version holds shell syntax fails', () async {
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0\$(id)', releaseJson: _releaseJson(prerelease: false)),
      [r'0.6.0$(id)'],
    );
  });

  test("a tag whose version isn't the pubspec version fails before reading the draft", () async {
    final gh = _FakeGh();
    await _expectProblems(
      _verify(
        assets,
        tag: '${tagPrefix}0.6.0',
        releaseJson: 'not read',
        gh: gh,
        pubspecVersion: '0.6.1',
      ),
      ['${tagPrefix}0.6.0 names 0.6.0', 'pubspec.yaml at $_commit has 0.6.1'],
    );
    expect(gh.calls, isEmpty);
  });

  test('a formula that installs another version fails and names both versions', () async {
    _writeBuild(assets, homebrew: true, version: '0.5.9');
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
      ['$formulaAsset installs 0.5.9, not 0.6.0'],
    );
  });

  test('a formula that readFormula cannot read fails and names it', () async {
    _writeBuild(assets, homebrew: true);
    File(p.join(assets.path, formulaAsset)).writeAsStringSync('class SkillsLint < Formula\nend\n');
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: false)),
      ['$formulaAsset: The formula has 0 version lines'],
    );
  });

  test('a release that is published already fails and says to stage it', () async {
    _writeBuild(assets, homebrew: true);
    await _expectProblems(
      _verify(
        assets,
        tag: '${tagPrefix}0.6.0',
        releaseJson: _releaseJson(prerelease: false, draft: false),
      ),
      ['has no draft release', 'Build and tag a release'],
    );
  });

  test("a draft whose prerelease setting doesn't match its version fails", () async {
    _writeBuild(assets, homebrew: true);
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}0.6.0', releaseJson: _releaseJson(prerelease: true)),
      ['is marked as one'],
    );
    _writeBuild(assets, homebrew: false);
    await _expectProblems(
      _verify(assets, tag: '${tagPrefix}1.0.0-dev.1', releaseJson: _releaseJson(prerelease: false)),
      ['is not marked as one'],
    );
  });
}
