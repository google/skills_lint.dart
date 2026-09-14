// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/config_serializer.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('ConfigSerializer.toYamlString', () {
    test('formats scalar primitives and custom object fallbacks', () {
      expect(ConfigSerializer.toYamlString(null).trim(), equals('null'));
      expect(ConfigSerializer.toYamlString(true).trim(), equals('true'));
      expect(ConfigSerializer.toYamlString(false).trim(), equals('false'));
      expect(ConfigSerializer.toYamlString(123).trim(), equals('123'));
      expect(ConfigSerializer.toYamlString(3.14).trim(), equals('3.14'));
      expect(ConfigSerializer.toYamlString('hello').trim(), equals('hello'));
      expect(
        ConfigSerializer.toYamlString(Uri.parse('https://example.com')).trim(),
        equals('"https://example.com"'),
      );
    });

    test('quotes reserved YAML 1.2 keywords and ambiguous tokens', () {
      expect(ConfigSerializer.toYamlString('true').trim(), equals('"true"'));
      expect(ConfigSerializer.toYamlString('True').trim(), equals('"True"'));
      expect(ConfigSerializer.toYamlString('false').trim(), equals('"false"'));
      expect(ConfigSerializer.toYamlString('null').trim(), equals('"null"'));
      expect(ConfigSerializer.toYamlString('~').trim(), equals('"~"'));
      expect(ConfigSerializer.toYamlString('').trim(), equals('""'));
      expect(ConfigSerializer.toYamlString('123').trim(), equals('"123"'));
    });

    test('escapes control characters and quotes', () {
      final String newline = ConfigSerializer.toYamlString('line 1\nline 2');
      expect(newline, contains(r'\n'));

      final String crlf = ConfigSerializer.toYamlString('line 1\r\nline 2');
      expect(crlf, contains(r'\r'));

      final String quotes = ConfigSerializer.toYamlString('hello "world"');
      expect(quotes, contains(r'\"'));

      final String tabs = ConfigSerializer.toYamlString('tab\tseparated');
      expect(tabs, contains(r'\t'));

      final String backspaceFormfeed = ConfigSerializer.toYamlString('a\bb\fc');
      expect(backspaceFormfeed, contains(r'\b'));
      expect(backspaceFormfeed, contains(r'\f'));

      final String backslash = ConfigSerializer.toYamlString(r'path\to\file');
      expect(backslash, contains(r'\\'));
    });

    test('formats empty collections', () {
      expect(ConfigSerializer.toYamlString(<String, Object?>{}).trim(), equals('{}'));
      expect(ConfigSerializer.toYamlString(<Object?>[]).trim(), equals('[]'));
    });

    test('formats simple maps and lists including quoted map keys', () {
      final map = <String, Object?>{
        'key1': 'value1',
        'key2': 42,
        'key3': true,
        'true': 'quoted_bool_key',
        'key with spaces': 'spaced_key',
      };
      final String yamlMap = ConfigSerializer.toYamlString(map);
      expect(yamlMap, contains('key1: value1'));
      expect(yamlMap, contains('key2: 42'));
      expect(yamlMap, contains('key3: true'));
      expect(yamlMap, contains('"true": quoted_bool_key'));
      expect(yamlMap, contains('"key with spaces": spaced_key'));

      final list = <Object?>['first', 'second', 3];
      final String yamlList = ConfigSerializer.toYamlString(list);
      expect(yamlList, contains('- first'));
      expect(yamlList, contains('- second'));
      expect(yamlList, contains('- 3'));
    });

    test('formats nested maps and lists with proper indentation', () {
      final data = <String, Object?>{
        'section': {
          'items': ['a', 'b'],
          'empty_map': <String, Object?>{},
          'empty_list': <Object?>[],
          'nested': {'deep_key': 'deep_val'},
        },
        'list_of_maps': [
          {
            'name': 'item1',
            'submap': {'foo': 'bar'},
            'sublist': ['x', 'y'],
          },
          {'name': 'item2'},
        ],
        'list_of_lists': [
          ['inner1', 'inner2'],
        ],
      };

      final String yaml = ConfigSerializer.toYamlString(data);
      expect(yaml, contains('section:'));
      expect(yaml, contains('  items:'));
      expect(yaml, contains('    - a'));
      expect(yaml, contains('    - b'));
      expect(yaml, contains('  empty_map: {}'));
      expect(yaml, contains('  empty_list: []'));
      expect(yaml, contains('  nested:'));
      expect(yaml, contains('    deep_key: deep_val'));
      expect(yaml, contains('- name: item1'));
      expect(yaml, contains('  submap:'));
      expect(yaml, contains('    foo: bar'));
      expect(yaml, contains('  sublist:'));
      expect(yaml, contains('    - x'));
      expect(yaml, contains('    - y'));

      final Object? parsed = loadYaml(yaml);
      expect(parsed, isNotNull);
    });

    test('scalar quoting and escaping round-trips all tricky tokens cleanly', () {
      final testCases = <String>[
        '007',
        '0x1F',
        '0o17',
        '-',
        '-1',
        '+1',
        '.5',
        '1.2.3',
        '1e5',
        'true',
        'false',
        'True',
        'False',
        'TRUE',
        'FALSE',
        'null',
        'Null',
        'NULL',
        '~',
        'yes',
        'no',
        'on',
        'off',
        'nan',
        'inf',
        '+inf',
        '-inf',
        'infinity',
        'check-relative-paths',
        'skills/nested',
        '../../.agents/skills',
        '~/my-skill',
        'foo: bar',
        '#comment',
        'hello\nworld',
        'line1\r\nline2',
        'tab\tseparated',
        'quoted "double" and \'single\'',
        'special chars: @ ` | > % & * ! ? [ ] { } ,',
        'null byte: \x00',
        'control char: \x1f',
        'del char: \x7f',
        'unicode: 🚀 🎯 — «»',
      ];

      for (final s in testCases) {
        final String yaml = ConfigSerializer.toYamlString(s);
        final Object? loaded = loadYaml(yaml);
        expect(
          loaded,
          equals(s),
          reason: 'Failed to round-trip scalar: "$s" (emitted YAML: $yaml)',
        );
      }
    });
  });
}
