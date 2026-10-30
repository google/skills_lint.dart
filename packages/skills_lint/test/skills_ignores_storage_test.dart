// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:skills_lint/src/skills_ignores_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late SkillsIgnoresStorage storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('storage_test.');
    storage = SkillsIgnoresStorage();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('SkillsIgnoresStorage.load Integration', () {
    test('inflates empty JSON into empty skills map', () async {
      final file = File('${tempDir.path}/empty.json');
      await file.writeAsString('{}');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills.isEmpty, isTrue);
      expect(result.problems, isEmpty);
    });

    test('inflates single skill with 1 ignore', () async {
      final file = File('${tempDir.path}/one_ignore.json');
      await file.writeAsString('''
{
  "skills": {
    "skill-a": [
      {"rule_id": "rule1", "file_name": "file1.md"}
    ]
  }
}
''');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills.containsKey('skill-a'), isTrue);
      expect(result.ignores.skills['skill-a']!.length, equals(1));
      expect(result.problems, isEmpty);
    });

    test('inflates single skill with 2 ignores', () async {
      final file = File('${tempDir.path}/two_ignores.json');
      await file.writeAsString('''
{
  "skills": {
    "skill-a": [
      {"rule_id": "rule1", "file_name": "file1.md"},
      {"rule_id": "rule2", "file_name": "file1.md"}
    ]
  }
}
''');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills.containsKey('skill-a'), isTrue);
      expect(result.ignores.skills['skill-a']!.length, equals(2));
      expect(result.problems, isEmpty);
    });

    test('inflates three skills with varied ignores', () async {
      final file = File('${tempDir.path}/three_skills.json');
      await file.writeAsString('''
{
  "skills": {
    "skill-a": [{"rule_id": "rule1", "file_name": "file1.md"}],
    "skill-b": [{"rule_id": "rule1", "file_name": "file1.md"}, {"rule_id": "rule2", "file_name": "file1.md"}],
    "skill-c": [{"rule_id": "rule1", "file_name": "file1.md"}, {"rule_id": "rule2", "file_name": "file1.md"}, {"rule_id": "rule3", "file_name": "file1.md"}]
  }
}
''');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills.containsKey('skill-a'), isTrue);
      expect(result.ignores.skills.containsKey('skill-b'), isTrue);
      expect(result.ignores.skills.containsKey('skill-c'), isTrue);
      expect(result.ignores.skills['skill-a']!.length, equals(1));
      expect(result.ignores.skills['skill-b']!.length, equals(2));
      expect(result.ignores.skills['skill-c']!.length, equals(3));
      expect(result.problems, isEmpty);
    });

    test('reports a file that is not valid JSON and loads no entries', () async {
      final file = File('${tempDir.path}/malformed.json');
      await file.writeAsString('{"skills": ');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills, isEmpty);
      expect(result.problems.map((problem) => problem.message), [
        allOf(contains(file.path), contains('is not valid JSON')),
      ]);
    });

    test('reports a skills value of the wrong shape and loads no entries', () async {
      final file = File('${tempDir.path}/wrong_shape.json');
      await file.writeAsString('{"skills": ["not", "a", "map"]}');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills, isEmpty);
      expect(result.problems.map((problem) => problem.message), [
        allOf(contains(file.path), contains('"skills"')),
      ]);
    });

    test('reports a top level that is not an object', () async {
      final file = File('${tempDir.path}/array.json');
      await file.writeAsString('[]');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills, isEmpty);
      expect(result.problems.map((problem) => problem.message), [
        contains('must be a JSON object'),
      ]);
    });

    test('reports an object with no skills key', () async {
      final file = File('${tempDir.path}/typo.json');
      await file.writeAsString('{"skill": {"a": []}}');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills, isEmpty);
      expect(result.problems.map((problem) => problem.message), [
        '${file.path} is missing the "skills" key.',
      ]);
    });

    test('loads an empty or whitespace-only file as empty, with no problems', () async {
      final file = File('${tempDir.path}/blank.json');
      for (final content in ['', ' \n']) {
        await file.writeAsString(content);
        final IgnoresLoad result = await storage.load(file.path);
        expect(result.ignores.skills, isEmpty);
        expect(result.problems, isEmpty);
      }
    });

    test('reports no problems for a file that does not exist', () async {
      final IgnoresLoad result = await storage.load('${tempDir.path}/absent.json');
      expect(result.ignores.skills, isEmpty);
      expect(result.problems, isEmpty);
    });

    test('loads the well-formed entries and reports each malformed one', () async {
      final file = File('${tempDir.path}/partial.json');
      await file.writeAsString('''
{
  "skills": {
    "skill-a": [{"rule_id": "rule1", "file_name": "SKILL.md"}],
    "skill-b": [
      {"rule_id": "rule2", "file_name": "SKILL.md"},
      {"rule_id": "rule3"},
      "not an entry",
      {"rule_id": "rule4", "file_name": "SKILL.md", "subject": 7},
      {"file_name": 3}
    ],
    "skill-c": {"rule_id": "rule5", "file_name": "SKILL.md"}
  }
}
''');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills.keys, unorderedEquals(['skill-a', 'skill-b']));
      expect(result.ignores.skills['skill-a']!.single.ruleId, 'rule1');
      expect(result.ignores.skills['skill-b']!.single.ruleId, 'rule2');
      expect(result.problems.map((problem) => problem.message), [
        '${file.path}: skill "skill-b", entry 2: missing "file_name".',
        '${file.path}: skill "skill-b", entry 3: must be a JSON object.',
        '${file.path}: skill "skill-b", entry 4: "subject" must be a string.',
        '${file.path}: skill "skill-b", entry 5: missing "rule_id"; "file_name" must be a string.',
        '${file.path}: skill "skill-c" must list its entries in a JSON array.',
      ]);
    });

    test('omits a skill whose entries are all malformed', () async {
      final file = File('${tempDir.path}/all_malformed.json');
      await file.writeAsString('{"skills": {"skill-a": [{"rule_id": "rule1"}]}}');

      final IgnoresLoad result = await storage.load(file.path);
      expect(result.ignores.skills, isEmpty);
      expect(result.problems, hasLength(1));
    });
  });
}
