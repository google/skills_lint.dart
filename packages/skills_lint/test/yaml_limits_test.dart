// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/yaml_limits.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

void main() {
  Matcher throwsYamlMessage(Matcher message) =>
      throwsA(isA<YamlException>().having((YamlException e) => e.message, 'message', message));

  // Each timeout in this file guards a document that package:yaml takes
  // minutes or longer to load without the limits, so a regression fails
  // quickly instead of hanging the test run.

  group('YamlLimits.loadYaml', () {
    test('returns the value of a document within the limits', () {
      expect(YamlLimits.loadYaml('a: &a [1, 2]\nb: *a\n'), {
        'a': [1, 2],
        'b': [1, 2],
      });
    });

    test('stops expanding aliases at the node limit', () {
      // Nine levels of ten aliases each expand to 10^9 values, which take
      // minutes to walk.
      for (final flowStyle in [false, true]) {
        expect(
          () => YamlLimits.loadYaml(billionLaughs(flowStyle: flowStyle)),
          throwsYamlMessage(
            equals(
              'The YAML holds more than ${YamlLimits.maxNodes} values once aliases are expanded.',
            ),
          ),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('reports an alias mapping key without loading it', () {
      // Each level doubles the one before, and package:yaml hashes the full
      // expansion of the key, so loading 40 levels takes about 2^40 steps.
      final buffer = StringBuffer('a0: &a0 [x, x]\n');
      for (var level = 1; level < 40; level++) {
        buffer.writeln('a$level: &a$level [*a${level - 1}, *a${level - 1}]');
      }
      buffer.writeln('k:\n  *a39 : value');

      expect(
        () => YamlLimits.loadYaml(buffer.toString()),
        throwsYamlMessage(startsWith('Mapping keys must be plain or quoted scalars')),
      );
    }, timeout: const Timeout(Duration(seconds: 5)));
  });

  group('YamlLimits.loadPubspec', () {
    test('parses a pubspec within the limits', () {
      expect(YamlLimits.loadPubspec('name: my_pkg\n').name, 'my_pkg');
    });

    test('reports a pubspec over the limits before Pubspec.parse reads it', () {
      expect(
        () => YamlLimits.loadPubspec('name: my_pkg\nnested: ${'[' * 70}${']' * 70}\n'),
        throwsYamlMessage(contains('levels deep')),
      );
    });
  });
}
