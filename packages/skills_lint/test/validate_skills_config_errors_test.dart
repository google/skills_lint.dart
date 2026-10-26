// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

/// Collects what is written to it, for use as `stderr` in [IOOverrides].
class _CapturingStdout implements Stdout {
  final StringBuffer buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  Future<void> flush() async {}

  /// Throws for any other member, so a test fails loudly if validation starts
  /// using one.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final String validSkillPath = p.normalize(p.absolute(p.join('example', 'skills', 'valid')));

void main() {
  group('validateSkills with configuration errors', () {
    /// Runs `validateSkills` on the valid example skill with the
    /// configuration parsed from [yaml], and returns its result and the text
    /// it wrote to standard error.
    Future<(bool, String, Configuration)> validate(String yaml) async {
      final Configuration config = ConfigParser.parse(yaml);
      final err = _CapturingStdout();
      final bool passed = await IOOverrides.runZoned(
        () => validateSkills(individualSkillPaths: [validSkillPath], config: config, quiet: true),
        stderr: () => err,
      );
      return (passed, err.buffer.toString(), config);
    }

    test('prints an unknown rule parameter as a warning and passes', () async {
      final (bool passed, String err, Configuration config) = await validate('''
skills_lint:
  rules:
    check-relative-paths:
      severity: error
      within-skil: true
''');

      expect(config.parsingErrors, hasLength(1));
      expect(
        err,
        contains(
          'Configuration warning: Global rules: Unrecognized parameter "within-skil" '
          'for rule "check-relative-paths".',
        ),
      );
      expect(passed, isTrue);
    });

    test('prints every configuration error', () async {
      final (_, String err, Configuration config) = await validate('''
skills_lint:
  bogus: 1
  rules:
    check-relative-paths:
      within-skill: maybe
''');

      expect(config.parsingErrors, hasLength(2));
      for (final String error in config.parsingErrors) {
        expect(err, contains('Configuration warning: $error'));
      }
    });

    test('prints no configuration warning for a valid configuration', () async {
      final (bool passed, String err, Configuration config) = await validate('''
skills_lint:
  rules:
    check-relative-paths:
      severity: error
      within-skill: true
''');

      expect(config.parsingErrors, isEmpty);
      expect(err, isNot(contains('Configuration warning')));
      expect(passed, isTrue);
    });
  });
}
