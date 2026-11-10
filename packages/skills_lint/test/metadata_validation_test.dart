// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/disallowed_field_rule.dart';
import 'package:skills_lint/src/rules/valid_yaml_metadata_rule.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:skills_lint/src/yaml_limits.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

void main() {
  group('Metadata (YAML) Validation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('metadata_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fails if YAML metadata is invalid', () async {
      await File('${tempDir.path}/SKILL.md').writeAsString('''
---
invalid: yaml: frontmatter
---
Body''');
      final validator = Validator();
      final ValidationResult result = await validator.validate(tempDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Invalid YAML metadata')));
    });

    test('fails if required field "name" is missing', () async {
      await File('${tempDir.path}/SKILL.md').writeAsString('''
---
description: A test skill
---
Body''');
      final validator = Validator();
      final ValidationResult result = await validator.validate(tempDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Missing required field: name')));
    });

    test('fails if required field "description" is missing', () async {
      await File('${tempDir.path}/SKILL.md').writeAsString('''
---
name: metadata-test
---
Body''');
      final validator = Validator();
      final ValidationResult result = await validator.validate(tempDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Missing required field: description')));
    });

    test('fails if required field "name" is present but empty', () async {
      await File('${tempDir.path}/SKILL.md').writeAsString('''
---
name:
description: A test skill
---
Body''');
      final validator = Validator();
      final ValidationResult result = await validator.validate(tempDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Missing required field: name')));
    });

    test('fails if required field "description" is present but empty', () async {
      await File('${tempDir.path}/SKILL.md').writeAsString('''
---
name: metadata-test
description:
---
Body''');
      final validator = Validator();
      final ValidationResult result = await validator.validate(tempDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Missing required field: description')));
    });

    test('passes without warning if disallowed fields are present', () async {
      final skillDir = Directory('${tempDir.path}/metadata-test');
      await skillDir.create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: metadata-test
description: A test skill
extra-field: not allowed
---
Body''');

      final validator = Validator();
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);

      final Iterable<ValidationError> disallowedErrors = result.validationErrors.where(
        (e) => e.ruleId == DisallowedFieldRule.ruleName,
      );
      expect(disallowedErrors, isEmpty);
    });

    test('passes with all allowed fields and valid YAML', () async {
      await File('${tempDir.path}/SKILL.md').writeAsString('''
---
name: metadata-test
description: A test skill
license: MIT
compatibility: Python 3.10
metadata:
  version: 1.0.0
allowed-tools: git
---
Body''');
      final validator = Validator();
      // We need to make sure directory name matches name in metadata
      final skillDir = Directory('${tempDir.path}/metadata-test');
      await skillDir.create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'metadata-test')}Body');

      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue, reason: result.errors.isEmpty ? '' : result.errors.first);
      expect(result.errors, isEmpty);
    });

    test(
      'reports accurate 1-based line number for missing required field and invalid yaml',
      () async {
        final skillDir = Directory('${tempDir.path}/test-skill')..createSync();
        const content =
            '---\n'
            'description: A test skill without name\n'
            '---\n'
            'Body\n';
        await File('${skillDir.path}/SKILL.md').writeAsString(content);
        final rule = ValidYamlMetadataRule();
        final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(content);
        final parsedYaml = loadYaml(match!.group(1)!) as YamlMap?;
        final context = SkillContext(
          directory: skillDir,
          rawContent: content,
          parsedYaml: parsedYaml,
        );

        final List<ValidationError> errors = await rule.validate(context);
        expect(errors, hasLength(1));
        expect(errors.first.ruleId, 'valid-yaml-metadata');
        expect(errors.first.region?.startLine, 1);
      },
    );

    test('reports accurate 1-based line number for disallowed field', () async {
      final skillDir = Directory('${tempDir.path}/metadata-test')..createSync();
      const content =
          '---\n'
          'name: metadata-test\n'
          'description: A test skill\n'
          'extra-field: not allowed\n'
          '---\n'
          'Body\n';
      await File('${skillDir.path}/SKILL.md').writeAsString(content);

      final rule = DisallowedFieldRule(severity: AnalysisSeverity.error);
      final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(content);
      final parsedYaml = loadYaml(match!.group(1)!) as YamlMap?;
      final context = SkillContext(
        directory: skillDir,
        rawContent: content,
        parsedYaml: parsedYaml,
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, hasLength(1));
      expect(errors.first.ruleId, 'disallowed-field');
      expect(errors.first.region?.startLine, 4);
    });
  });

  group('YAML size limits', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('yaml_limits_test.');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<ValidationResult> validateFrontmatter(String frontmatter) async {
      await File('${tempDir.path}/SKILL.md').writeAsString('---\n$frontmatter---\nBody\n');
      return Validator().validate(tempDir);
    }

    ValidationError onlyYamlError(ValidationResult result) => result.validationErrors.singleWhere(
      (ValidationError error) => error.ruleId == ValidYamlMetadataRule.ruleName,
      orElse: () => fail('No valid-yaml-metadata error in: ${result.validationErrors}'),
    );

    test('rejects an anchor and names it with its line', () async {
      final ValidationResult result = await validateFrontmatter(
        'name: shared\ndescription: &text A skill.\nmetadata:\n  summary: *text\n',
      );

      expect(result.context?.parsedYaml, isNull);
      expect(
        onlyYamlError(result).message,
        allOf(
          contains('line 2, column 14'),
          contains(
            "`&text` is a YAML anchor. SKILL.md frontmatter doesn't support anchors (`&`) or "
            'aliases (`*`). Write the value out in full.',
          ),
        ),
      );
    });

    test('rejects an alias used as a mapping key before parsing', () async {
      // Loading this would hash all 10^9 values of the key. The scan of the
      // text rejects it first.
      final ValidationResult result = await validateFrontmatter(
        '${_billionLaughs(flowStyle: true).replaceFirst(RegExp(r'description: \*i\n$'), '')}'
        'description: d\n? *i\n: value\n',
      );

      expect(onlyYamlError(result).message, contains('`&a` is a YAML anchor'));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('rejects alias expansion over the node limit before anything reads the value', () {
      // Nine levels of ten aliases each expand to 10^9 values.
      for (final flowStyle in [false, true]) {
        expect(
          () => YamlLimits.load(_billionLaughs(flowStyle: flowStyle)),
          throwsA(
            isA<YamlException>().having(
              (YamlException e) => e.message,
              'message',
              'The YAML holds more than ${YamlLimits.maxNodes} values once aliases are expanded.',
            ),
          ),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('rejects block nesting deeper than the limit', () async {
      final String deep = [
        for (var level = 0; level <= YamlLimits.maxDepth; level++) '${'  ' * level}k$level:',
      ].join('\n');
      final ValidationResult result = await validateFrontmatter(
        'name: deep\ndescription: d\n$deep x\n',
      );

      expect(result.context?.parsedYaml, isNull);
      expect(
        onlyYamlError(result).message,
        contains('nests more than ${YamlLimits.maxDepth} levels deep'),
      );
    });

    test('rejects nesting deep enough to overflow the parser stack', () async {
      // `- - x` is a list inside a list, so this line nests 100,000 levels
      // in about 200 KB, which overflows the parser's stack.
      final ValidationResult result = await validateFrontmatter(
        'name: deep\nitems:\n  ${'- ' * 100000}x\n',
      );

      expect(onlyYamlError(result).message, contains('levels deep'));
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('rejects flow nesting by counting brackets before parsing', () async {
      const levels = 200000;
      final ValidationResult result = await validateFrontmatter(
        'name: deep\ndescription: ${'[' * levels}${']' * levels}\n',
      );

      expect(
        onlyYamlError(result).message,
        contains('more than the limit of ${YamlLimits.maxFlowCollectionStarts}'),
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('accepts frontmatter with nesting and star or ampersand text', () async {
      final ValidationResult result = await validateFrontmatter('''
name: shared
description: Use *bold* text & more. # a comment with *star
metadata:
  url: "https://example.com/?a=1&b=2"
  notes: |
    *bold* and &amp;
  levels: [[[[[[[[1]]]]]]]]
''');

      expect(result.context?.parsedYaml, isNotNull);
      expect(
        result.validationErrors.where((e) => e.ruleId == ValidYamlMetadataRule.ruleName),
        isEmpty,
      );
    });

    test('accepts brackets in text, which count toward the limit but do not nest', () async {
      final ValidationResult result = await validateFrontmatter(
        'name: links\ndescription: d\nmetadata:\n  notes: "${'[link](https://example.com) ' * 2000}"\n',
      );

      expect(result.context?.parsedYaml, isNotNull);
    });
  });
}

/// A frontmatter whose `description` expands to 10^9 values through nine
/// levels of ten aliases each.
String _billionLaughs({required bool flowStyle}) {
  const levels = 'abcdefghi';
  final buffer = StringBuffer('name: demo\n');
  for (var i = 0; i < levels.length; i++) {
    final item = i == 0 ? 'x' : '*${levels[i - 1]}';
    final items = List<String>.filled(10, item);
    buffer.writeln(
      flowStyle
          ? '${levels[i]}: &${levels[i]} [${items.join(', ')}]'
          : '${levels[i]}: &${levels[i]}\n${items.map((String it) => '  - $it').join('\n')}',
    );
  }
  buffer.writeln('description: *${levels[levels.length - 1]}');
  return buffer.toString();
}
