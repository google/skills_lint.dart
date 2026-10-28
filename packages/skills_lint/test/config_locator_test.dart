// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_locator.dart';
import 'package:test/test.dart';

void main() {
  group('lineOfRuleKey', () {
    late Directory tempDir;
    late String configFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('config_locator_test.');
      configFile = p.join(tempDir.path, 'skills_lint.yaml');
      File(configFile).writeAsStringSync('''
skills_lint:
  rules:
    top-rule: error
  individual_skills:
    - path: one
      rules:
        skill-rule: warning
''');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('finds a top-level rule name', () {
      expect(
        lineOfRuleKey(configFile, (section: 'rules', entryIndex: null, ruleName: 'top-rule')),
        3,
      );
    });

    test('finds a rule name in a target entry', () {
      expect(
        lineOfRuleKey(configFile, (
          section: 'individual_skills',
          entryIndex: 0,
          ruleName: 'skill-rule',
        )),
        7,
      );
    });

    test('returns null for a missing name, a missing entry, or a missing file', () {
      expect(
        lineOfRuleKey(configFile, (section: 'rules', entryIndex: null, ruleName: 'absent')),
        isNull,
      );
      expect(
        lineOfRuleKey(configFile, (
          section: 'individual_skills',
          entryIndex: 1,
          ruleName: 'skill-rule',
        )),
        isNull,
      );
      expect(
        lineOfRuleKey(p.join(tempDir.path, 'missing.yaml'), (
          section: 'rules',
          entryIndex: null,
          ruleName: 'top-rule',
        )),
        isNull,
      );
    });
  });
}
