// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/action_pins.dart';
import '../src/models/action_pin.dart';
import '../src/models/convention_violation.dart';

const String _checkout = 'actions/checkout';
const String _sha = '3d3c42e5aac5ba805825da76410c181273ba90b1';
const String _otherSha = '0000000000000000000000000000000000000000';

/// Runs the action pin detectors over small inline workflows, which pins what
/// each one reports independently of the repository's workflows.
void main() {
  group('actionPinFiles', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('action_pins_test.');
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    void createFiles(Map<String, String> files) {
      for (final MapEntry(key: path, value: content) in files.entries) {
        File(p.joinAll([root.path, ...path.split('/')]))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
      }
    }

    List<String> scannedPaths() => [
      for (final File file in actionPinFiles(root.path))
        p.posix.joinAll(p.split(p.relative(file.path, from: root.path))),
    ];

    /// A workflow file with one job whose steps use each of [uses] in order.
    ///
    /// The document is built as a map and written as indented JSON, which
    /// YAML parsers read as YAML, so no fixture depends on hand-written YAML
    /// indentation. Each `uses` value sits on its own line.
    String workflowUsing(List<String> uses) => _yaml({
      'jobs': {
        'build': {
          'steps': [
            for (final u in uses) {'uses': u},
          ],
        },
      },
    });

    /// An `action.yaml` for a composite action whose steps use each of [uses]
    /// in order.
    ///
    /// It is built like [workflowUsing].
    String actionUsing(List<String> uses) => _yaml({
      'runs': {
        'using': 'composite',
        'steps': [
          for (final u in uses) {'uses': u},
        ],
      },
    });

    test('lists workflows and the actions they use, and nothing else under .github', () {
      createFiles({
        '.github/workflows/ci.yaml': workflowUsing(['./.github/actions/tap']),
        '.github/workflows/release.yaml': workflowUsing(['$_checkout@$_sha']),
        '.github/workflows/notes.md': '',
        '.github/actions/tap/action.yaml': actionUsing(['$_checkout@$_sha']),
        '.github/actions/tap/README.md': '',
        '.github/actions/unused/action.yaml': actionUsing(['$_checkout@$_otherSha']),
        '.github/dependabot.yaml': '',
        '.github/FUNDING.yml': '',
      });
      expect(scannedPaths(), [
        '.github/actions/tap/action.yaml',
        '.github/workflows/ci.yaml',
        '.github/workflows/release.yaml',
      ]);
    });

    test('lists an action outside .github that a workflow uses', () {
      createFiles({
        '.github/workflows/ci.yaml': workflowUsing(['./tools/my-action']),
        'tools/my-action/action.yaml': actionUsing(['$_checkout@$_sha']),
      });
      expect(scannedPaths(), ['.github/workflows/ci.yaml', 'tools/my-action/action.yaml']);
    });

    test('follows an action that another action uses, and stops at a cycle', () {
      createFiles({
        '.github/workflows/ci.yaml': workflowUsing(['./outer']),
        'outer/action.yaml': actionUsing(['./inner']),
        'inner/action.yaml': actionUsing(['./outer', '$_checkout@$_sha']),
      });
      expect(scannedPaths(), [
        '.github/workflows/ci.yaml',
        'inner/action.yaml',
        'outer/action.yaml',
      ]);
    });

    test('skips a local reusable workflow, which the workflow scan covers', () {
      createFiles({
        '.github/workflows/ci.yaml':
            'jobs:\n  call:\n    uses: ./.github/workflows/reusable.yaml\n',
        '.github/workflows/reusable.yaml': workflowUsing(['$_checkout@$_sha']),
      });
      expect(scannedPaths(), ['.github/workflows/ci.yaml', '.github/workflows/reusable.yaml']);
    });

    test('fails on a local uses that names no action file, naming the file, line and path', () {
      final String workflow = workflowUsing(['$_checkout@$_sha', './tools/gone']);
      final int goneLine =
          const LineSplitter().convert(workflow).indexWhere((l) => l.contains('./tools/gone')) + 1;
      createFiles({'.github/workflows/ci.yaml': workflow, 'tools/gone/README.md': ''});
      expect(
        () => actionPinFiles(root.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('${p.join('.github', 'workflows', 'ci.yaml')}:$goneLine:'),
              contains('./tools/gone'),
            ),
          ),
        ),
      );
    });

    test('fails on a .yml workflow or a used action.yml, naming each, rather than skipping it', () {
      createFiles({
        '.github/workflows/ci.yaml': workflowUsing(['./.github/actions/tap']),
        '.github/workflows/old.yml': '',
        '.github/actions/tap/action.yml': '',
        '.github/actions/digests/action.yaml': '',
      });
      expect(
        () => actionPinFiles(root.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains(p.join('workflows', 'old.yml')),
              isNot(contains('ci.yaml')),
              isNot(contains('digests')),
            ),
          ),
        ),
      );
    });

    test('fails on an action.yml that a workflow uses', () {
      createFiles({
        '.github/workflows/ci.yaml': workflowUsing(['./.github/actions/tap']),
        '.github/actions/tap/action.yml': '',
      });
      expect(
        () => actionPinFiles(root.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(p.join('tap', 'action.yml')),
          ),
        ),
      );
    });

    test('fails on .github/dependabot.yml, which Dependabot reads before dependabot.yaml', () {
      createFiles({
        '.github/workflows/ci.yaml': '',
        '.github/dependabot.yaml': '',
        '.github/dependabot.yml': '',
      });
      expect(
        () => actionPinFiles(root.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains(p.join('.github', 'dependabot.yml')),
              isNot(contains('dependabot.yaml')),
            ),
          ),
        ),
      );
    });

    test('fails when .github/workflows is missing, rather than checking nothing', () {
      createFiles({'.github/dependabot.yaml': ''});
      expect(
        () => actionPinFiles(root.path),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('workflows'))),
      );
    });
  });

  group('findActionPins', () {
    test('reads step and job uses with their line, ref and version comment', () {
      final List<ActionPin> pins = findActionPins('ci.yaml', '''
jobs:
  build:
    steps:
      - uses: $_checkout@$_sha # v7.0.1
        with:
          persist-credentials: false
      - run: echo hi
  health:
    uses: dart-lang/ecosystem/.github/workflows/health.yaml@$_sha # main
''');
      expect(_describe(pins), [
        'ci.yaml:4 $_checkout @$_sha v7.0.1',
        'ci.yaml:9 dart-lang/ecosystem/.github/workflows/health.yaml @$_sha main',
      ]);
    });

    test('keeps only the first word of the comment and reads quoted values', () {
      final List<ActionPin> pins = findActionPins('ci.yaml', '''
jobs:
  build:
    steps:
      - uses: owner/action@$_sha # v3 # zizmor: ignore[archived-uses]
      - uses: "$_checkout@$_sha" #v7.0.1
      - uses: '$_checkout@v7'
''');
      expect(_describe(pins), [
        'ci.yaml:4 owner/action @$_sha v3',
        'ci.yaml:5 $_checkout @$_sha v7.0.1',
        'ci.yaml:6 $_checkout @v7 null',
      ]);
    });

    test('reads the version comment in a file with CRLF line endings', () {
      final List<ActionPin> pins = findActionPins(
        'ci.yaml',
        'jobs:\r\n  build:\r\n    steps:\r\n      - uses: $_checkout@$_sha # v7.0.1\r\n',
      );
      expect(_describe(pins), ['ci.yaml:4 $_checkout @$_sha v7.0.1']);
    });

    test('splits Docker references at the digest or tag', () {
      final List<ActionPin> pins = findActionPins('ci.yaml', '''
jobs:
  build:
    steps:
      - uses: docker://alpine@sha256:abc # 3.20
      - uses: docker://ghcr.io:5000/owner/image:1.2
      - uses: docker://ghcr.io:5000/owner/image
''');
      expect(_describe(pins), [
        'ci.yaml:4 docker://alpine @sha256:abc 3.20',
        'ci.yaml:5 docker://ghcr.io:5000/owner/image :1.2 null',
        'ci.yaml:6 docker://ghcr.io:5000/owner/image  null',
      ]);
    });

    test('skips local references and uses: text outside a job or step', () {
      final List<ActionPin> pins = findActionPins('ci.yaml', '''
on:
  push:
jobs:
  build:
    steps:
      - uses: ./.github/actions/setup
      - run: |
          echo "uses: $_checkout@$_otherSha"
  reuse:
    uses: ./.github/workflows/build.yaml
''');
      expect(pins, isEmpty);
    });

    test("reads a composite action's step uses", () {
      final List<ActionPin> pins = findActionPins('.github/actions/tap/action.yaml', '''
name: Tap
runs:
  using: composite
  steps:
    - uses: $_checkout@$_sha # v7.0.1
    - shell: bash
      run: echo hi
    - uses: ./.github/actions/other
''');
      expect(_describe(pins), ['.github/actions/tap/action.yaml:5 $_checkout @$_sha v7.0.1']);
    });

    test('returns nothing for a file without jobs or runs', () {
      expect(findActionPins('ci.yaml', 'name: empty\n'), isEmpty);
    });
  });

  group('findInconsistentPins', () {
    test('accepts one pin per name, and different pins for different names', () {
      final pins = [
        ActionPin('a.yaml', 4, _checkout, '@$_sha', 'v7.0.1'),
        ActionPin('b.yaml', 9, _checkout, '@$_sha', 'v7.0.1'),
        ActionPin('a.yaml', 7, 'github/codeql-action/upload-sarif', '@$_otherSha', 'v4'),
        ActionPin('b.yaml', 3, 'github/codeql-action/init', '@$_sha', 'v4'),
      ];
      expect(findInconsistentPins(pins), isEmpty);
    });

    test('reports every use when one name has two refs', () {
      final List<ConventionViolation> violations = findInconsistentPins([
        ActionPin('b.yaml', 9, _checkout, '@$_sha', 'v7.0.1'),
        ActionPin('a.yaml', 4, _checkout, '@$_otherSha', 'v7.0.1'),
        ActionPin('a.yaml', 2, _checkout, '@$_sha', 'v7.0.1'),
      ]);
      expect(violations.map((v) => v.describe()), [
        'a.yaml:2: `$_checkout@$_sha # v7.0.1`, but other uses pin `@$_otherSha # v7.0.1`',
        'a.yaml:4: `$_checkout@$_otherSha # v7.0.1`, but other uses pin `@$_sha # v7.0.1`',
        'b.yaml:9: `$_checkout@$_sha # v7.0.1`, but other uses pin `@$_otherSha # v7.0.1`',
      ]);
    });

    test('reports a different or missing version comment on the same ref', () {
      final List<ConventionViolation> violations = findInconsistentPins([
        ActionPin('a.yaml', 4, _checkout, '@$_sha', 'v7.0.1'),
        ActionPin('b.yaml', 4, _checkout, '@$_sha', 'v7.0.0'),
        ActionPin('c.yaml', 4, _checkout, '@$_sha', null),
      ]);
      expect(violations.map((v) => v.describe()), [
        'a.yaml:4: `$_checkout@$_sha # v7.0.1`, but other uses pin `@$_sha # v7.0.0`, `@$_sha`',
        'b.yaml:4: `$_checkout@$_sha # v7.0.0`, but other uses pin `@$_sha # v7.0.1`, `@$_sha`',
        'c.yaml:4: `$_checkout@$_sha`, but other uses pin `@$_sha # v7.0.1`, `@$_sha # v7.0.0`',
      ]);
    });
  });
}

/// One line per pin: path, line, name, ref and comment, so a failure shows
/// every field.
List<String> _describe(List<ActionPin> pins) => [
  for (final pin in pins) '${pin.path}:${pin.line} ${pin.name} ${pin.ref} ${pin.comment}',
];

/// [document] as YAML text, one value per line.
///
/// JSON is a subset of YAML 1.2, so indented JSON is a valid workflow or
/// action file and needs no YAML writer.
String _yaml(Map<String, Object> document) => const JsonEncoder.withIndent('  ').convert(document);
