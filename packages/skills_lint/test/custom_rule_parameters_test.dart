// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:test/test.dart';

void main() {
  group('CustomRuleParameters', () {
    test('params map is unmodifiable', () {
      final parameters = CustomRuleParameters(const {'key': 'value'});

      expect(() => parameters.params['new_key'] = 'new_value', throwsA(isUnsupportedError));
      expect(() => parameters.params.remove('key'), throwsA(isUnsupportedError));
      expect(() => parameters.params.clear(), throwsA(isUnsupportedError));
    });

    test('ensures deep immutability for nested collections', () {
      final list = ['a', 'b'];
      final nestedMap = {'k': 'v'};
      final params = CustomRuleParameters({'items': list, 'nested': nestedMap});

      expect(() => (params['items']! as List<Object?>).add('c'), throwsUnsupportedError);
      expect(
        () => (params['nested']! as Map<String, Object?>)['new'] = 'val',
        throwsUnsupportedError,
      );
    });

    test('operator[], keys, and containsKey operate as expected', () {
      final params = CustomRuleParameters(const {'str': 'hello', 'count': 42});
      expect(params['str'], equals('hello'));
      expect(params['count'], equals(42));
      expect(params['nonexistent'], isNull);
      expect(params.containsKey('str'), isTrue);
      expect(params.containsKey('missing'), isFalse);
      expect(params.keys, containsAll(['str', 'count']));
      expect(params.isEmpty, isFalse);
      expect(params.isNotEmpty, isTrue);
    });

    test('getString returns string or null', () {
      final params = CustomRuleParameters(const {'str': 'hello', 'count': 42});
      expect(params.getString('str'), equals('hello'));
      expect(params.getString('count'), isNull);
      expect(params.getString('missing'), isNull);
    });

    test('methods serialize correctly', () {
      final params = CustomRuleParameters(const {
        'name': 'test',
        'count': 42,
        'enabled': false,
        'items': ['a', 'b'],
      });

      final Map<String, Object?> map = params.toYaml();
      expect(map['name'], equals('test'));
      expect(map['count'], equals(42));
      expect(map['enabled'], equals(false));
      expect(map['items'], equals(['a', 'b']));

      final String yamlStr = params.toYamlString();
      expect(yamlStr, contains('name: test'));
      expect(yamlStr, contains('count: 42'));
      expect(yamlStr, contains('enabled: false'));
    });
  });
}
