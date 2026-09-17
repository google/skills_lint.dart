// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/source_region.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('SkillContext offsetToLine', () {
    test('converts character offsets to 1-based line numbers accurately', () {
      final context = SkillContext(
        directory: Directory.current,
        rawContent: 'line1\nline2\nline3\nline4',
      );

      // 'l' of line1 (index 0)
      expect(context.offsetToLine(0), equals(1));
      // '\n' after line1 (index 5)
      expect(context.offsetToLine(5), equals(1));
      // 'l' of line2 (index 6)
      expect(context.offsetToLine(6), equals(2));
      // 'l' of line3 (index 12)
      expect(context.offsetToLine(12), equals(3));
      // 'l' of line4 (index 18)
      expect(context.offsetToLine(18), equals(4));
    });

    test('handles empty content and out of bound offsets gracefully', () {
      final context = SkillContext(directory: Directory.current, rawContent: '');

      expect(context.offsetToLine(0), equals(1));
      expect(context.offsetToLine(100), equals(1));
    });
  });

  group('SkillContext yamlNodeToRegion', () {
    test('resolves 1-based region for YAML frontmatter node', () {
      const content =
          '---\n'
          'name: test-skill\n'
          'description: A test skill\n'
          '---\n'
          'Body\n';

      final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(content);
      final parsedYaml = loadYaml(match!.group(1)!) as YamlMap;
      final context = SkillContext(
        directory: Directory.current,
        rawContent: content,
        parsedYaml: parsedYaml,
      );

      final SourceRegion? nameRegion = context.yamlNodeToRegion(parsedYaml.nodes['name']);
      expect(nameRegion, isNotNull);
      expect(nameRegion!.startLine, equals(2));
      expect(nameRegion.startColumn, equals(7));

      final SourceRegion? descRegion = context.yamlNodeToRegion(parsedYaml.nodes['description']);
      expect(descRegion, isNotNull);
      expect(descRegion!.startLine, equals(3));
      expect(descRegion.startColumn, equals(14));
    });

    test('returns null for null node or missing frontmatter', () {
      final context = SkillContext(directory: Directory.current, rawContent: 'No frontmatter here');

      expect(context.yamlNodeToRegion(null), isNull);
    });

    test('skillStartRegex matches CRLF line endings without trailing carriage return', () {
      const crlfContent = '---\r\nname: test-skill\r\ndescription: A test skill\r\n---\r\nBody\r\n';
      final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(crlfContent);
      expect(match, isNotNull);
      final String captured = match!.group(1)!;
      expect(captured.endsWith('\r'), isFalse);
      expect(captured, contains('name: test-skill'));
    });
  });
}
