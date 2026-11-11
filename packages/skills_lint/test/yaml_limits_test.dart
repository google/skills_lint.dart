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

  group('YamlLimits.maxBytes', () {
    // A document of [bytes] UTF-8 bytes: `a: `, then copies of [char], each
    // [charBytes] long, then a newline.
    String documentOf(int bytes, {String char = 'x', int charBytes = 1}) {
      final int fill = bytes - 'a: \n'.length;
      expect(fill % charBytes, 0, reason: 'the fill must be whole characters');
      return 'a: ${char * (fill ~/ charBytes)}\n';
    }

    String overLimitMessage(int bytes) =>
        'The YAML is ${_withCommas(bytes)} bytes, more than the limit of '
        '${_withCommas(YamlLimits.maxBytes)} bytes.';

    test('parses a document one byte under the limit', () {
      final Object? value = YamlLimits.loadYaml(documentOf(YamlLimits.maxBytes - 1));
      expect((value! as Map)['a'], hasLength(YamlLimits.maxBytes - 5));
    });

    test('parses a document exactly at the limit', () {
      final Object? value = YamlLimits.loadYaml(documentOf(YamlLimits.maxBytes));
      expect((value! as Map)['a'], hasLength(YamlLimits.maxBytes - 4));
    });

    test('reports a document one byte over the limit with its size', () {
      expect(
        () => YamlLimits.loadYaml(documentOf(YamlLimits.maxBytes + 1)),
        throwsYamlMessage(equals(overLimitMessage(YamlLimits.maxBytes + 1))),
      );
    });

    test('counts UTF-8 bytes, not characters', () {
      // `é` is one UTF-16 code unit and two UTF-8 bytes, and `😀` is two
      // code units and four bytes, so both documents are under the limit in
      // code units and over it in bytes.
      const int over = YamlLimits.maxBytes + 4;
      expect(
        () => YamlLimits.loadYaml(documentOf(over, char: 'é', charBytes: 2)),
        throwsYamlMessage(equals(overLimitMessage(over))),
      );
      expect(
        () => YamlLimits.loadYaml(documentOf(over, char: '😀', charBytes: 4)),
        throwsYamlMessage(equals(overLimitMessage(over))),
      );
      expect(YamlLimits.loadYaml(documentOf(YamlLimits.maxBytes, char: 'é', charBytes: 2)), isMap);
    });

    test('reports oversized frontmatter before scanning it for anchors', () {
      final yaml = '${documentOf(YamlLimits.maxBytes)}b: &anchor x\n';
      expect(
        () => YamlLimits.loadFrontmatter(yaml),
        throwsYamlMessage(equals(overLimitMessage(yaml.length))),
      );
    });

    test('reports an oversized pubspec before Pubspec.parse reads it', () {
      final yaml = 'name: my_pkg\n${documentOf(YamlLimits.maxBytes)}';
      expect(
        () => YamlLimits.loadPubspec(yaml),
        throwsYamlMessage(equals(overLimitMessage(yaml.length))),
      );
    });

    test('rejects a very large document quickly', () {
      // 64 MiB of flow collections would take package:yaml far longer than
      // the timeout to parse, and the other limits would also need a full
      // pass over the text.
      final String yaml = '[' * (64 * 1024 * 1024);
      final stopwatch = Stopwatch()..start();
      expect(
        () => YamlLimits.loadYaml(yaml),
        throwsYamlMessage(equals(overLimitMessage(yaml.length))),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    }, timeout: const Timeout(Duration(seconds: 10)));
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

/// Writes [count] with a comma between each group of three digits.
String _withCommas(int count) =>
    count.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
