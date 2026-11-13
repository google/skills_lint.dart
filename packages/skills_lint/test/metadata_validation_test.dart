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

    ValidationError onlyYamlError(ValidationResult result) => result.validationErrors.singleWhere(
      (ValidationError error) => error.ruleId == ValidYamlMetadataRule.ruleName,
      orElse: () => fail('No valid-yaml-metadata error in: ${result.validationErrors}'),
    );

    test('reports an anchor with its line and column', () async {
      final ValidationResult result = await validateFrontmatter(
        tempDir,
        'name: shared\ndescription: &text A skill.\nmetadata:\n  summary: *text\n',
      );

      expect(result.context?.parsedYaml, isNull);
      expect(
        onlyYamlError(result).message,
        allOf(
          contains('line 2, column 14'),
          contains(
            "`&text` is a YAML anchor. SKILL.md frontmatter doesn't support anchors (`&`) or "
            'aliases (`*`). Write the value out in full, or quote it.',
          ),
        ),
      );
    });

    // Each timeout in this group guards a document that package:yaml takes
    // minutes or longer to load without the limits, so a regression fails
    // quickly instead of hanging the test run.

    test('reports the anchor in a document with an alias mapping key without loading it', () async {
      // Loading this would hash all 10^9 values of the key. The scan of the
      // text rejects it first.
      final ValidationResult result = await validateFrontmatter(
        tempDir,
        '${billionLaughs(flowStyle: true).replaceFirst(RegExp(r'description: \*i\n$'), '')}'
        'description: d\n? *i\n: value\n',
      );

      expect(onlyYamlError(result).message, contains('`&a` is a YAML anchor'));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('reports nested collection keys without loading them', () async {
      // package:yaml hashes each collection key again at every level of
      // nesting, so loading these 30 levels takes about 3^30 steps.
      final ValidationResult result = await validateFrontmatter(
        tempDir,
        'name: keys\ndescription: d\nk: ${'{' * 30}a${'}' * 30}\n',
      );

      expect(
        onlyYamlError(result).message,
        contains('Mapping keys must be plain or quoted scalars'),
      );
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('reports an explicit key', () async {
      final ValidationResult result = await validateFrontmatter(
        tempDir,
        'name: keys\ndescription: d\n? k\n: value\n',
      );

      expect(
        onlyYamlError(result).message,
        contains('Mapping keys must be plain or quoted scalars'),
      );
    });

    test('reports block nesting deeper than the limit', () async {
      final String deep = [
        for (var level = 0; level <= YamlLimits.maxDepth; level++) '${'  ' * level}k$level:',
      ].join('\n');
      final ValidationResult result = await validateFrontmatter(
        tempDir,
        'name: deep\ndescription: d\n$deep x\n',
      );

      expect(result.context?.parsedYaml, isNull);
      expect(
        onlyYamlError(result).message,
        contains('nests more than ${YamlLimits.maxDepth} levels deep'),
      );
    });

    test('reports nesting deep enough to overflow the parser stack', () async {
      // `- - x` is a list inside a list, so this line nests 20,000 levels
      // in about 40 KB, under YamlLimits.maxBytes. The parser's stack
      // overflows at about 5,000 levels.
      final ValidationResult result = await validateFrontmatter(
        tempDir,
        'name: deep\nitems:\n  ${'- ' * 20000}x\n',
      );

      expect(onlyYamlError(result).message, contains('levels deep'));
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('reports too many brackets without parsing', () async {
      // Twice the bracket limit, in about 40 KB, under YamlLimits.maxBytes.
      // package:yaml slows down with the square of flow nesting, so parsing
      // this many levels takes about two seconds.
      const int levels = 2 * YamlLimits.maxFlowCollectionStarts;
      final ValidationResult result = await validateFrontmatter(
        tempDir,
        'name: deep\ndescription: ${'[' * levels}${']' * levels}\n',
      );

      expect(
        onlyYamlError(result).message,
        contains('more than the limit of ${YamlLimits.maxFlowCollectionStarts}'),
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('accepts nesting and text with stars and ampersands', () async {
      final ValidationResult result = await validateFrontmatter(tempDir, '''
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
        tempDir,
        'name: links\ndescription: d\nmetadata:\n  notes: "${'[link](https://example.com) ' * 2000}"\n',
      );

      expect(result.context?.parsedYaml, isNotNull);
    });
  });
}
