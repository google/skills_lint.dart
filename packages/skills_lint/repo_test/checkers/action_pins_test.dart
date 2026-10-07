// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/action_pins.dart';
import '../src/models/convention_violation.dart';

const String _checkout = 'actions/checkout';
const String _sha = '3d3c42e5aac5ba805825da76410c181273ba90b1';
const String _otherSha = '0000000000000000000000000000000000000000';

/// Runs the action pin detectors over small inline workflows, which pins what
/// each one reports independently of the repository's workflows.
void main() {
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

    test('returns nothing for a file without jobs', () {
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
