// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/description_yaml_comment_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

const String _flag = '--${DescriptionYamlCommentRule.ruleName}';

/// A `SKILL.md` with the given frontmatter lines between the `---` delimiters.
String _skill(String frontmatter) => '---\n$frontmatter\n---\n\n# Body\n';

SkillContext _context(String rawContent) {
  final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(rawContent);
  return SkillContext(
    directory: Directory('demo-skill'),
    rawContent: rawContent,
    parsedYaml: match == null ? null : loadYaml(match.group(1)!) as YamlMap?,
  );
}

void main() {
  final rule = DescriptionYamlCommentRule(severity: AnalysisSeverity.error);

  group('DescriptionYamlCommentRule reports', () {
    test('an unquoted description that " #" cuts short', () async {
      final SkillContext context = _context(
        _skill(
          'name: demo-skill\n'
          'description: Fix bugs. Use when asked "fix #123" or "close #45".',
        ),
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors, hasLength(1));
      final ValidationError error = errors.single;
      expect(error.ruleId, 'description-yaml-comment');
      expect(error.severity, AnalysisSeverity.error);
      expect(error.file, 'SKILL.md');
      expect(error.subject, '#123" or "close #45".');
      expect(
        error.message,
        'Description field is cut short by a YAML comment. In an unquoted value, '
        '" #" starts a comment, so the description ends at |HERE| (line 3, column 44). '
        'Quote the value (description: "...") or use a block scalar (description: >-). '
        'Cutoff: Fix bugs. Use when asked "fix|HERE| #123" or "close #45".',
      );
      expect(
        error.markdownMessage,
        '**Frontmatter `description` is cut short by a YAML comment.**\n\n'
        'In an unquoted value, ` #` starts a comment, so the description ends at '
        '**|HERE|** (line 3, column 44).\n\n'
        '**Cutoff excerpt:**\n'
        '> Fix bugs. Use when asked "fix**|HERE|** #123" or "close #45".\n\n'
        '**How to fix:**\n'
        '- Quote the value (`description: "..."`), or write it as a block scalar '
        '(`description: >-`).',
      );
      expect(error.region?.startLine, 3);
      expect(error.region?.startColumn, 44);
      expect(error.region?.endLine, 3);
      expect(error.region?.endColumn, 44 + '#123" or "close #45".'.length);
    });

    test('a multi-line unquoted description cut short on a continuation line', () async {
      final SkillContext context = _context(
        _skill(
          'name: demo-skill\n'
          'description: Fix bugs.\n'
          '  Use when asked "fix #123".',
        ),
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors, hasLength(1));
      expect(errors.single.subject, '#123".');
      expect(errors.single.message, contains('(line 4, column 23)'));
      expect(errors.single.message, endsWith('Cutoff: Fix bugs. Use when asked "fix|HERE| #123".'));
      expect(errors.single.region?.startLine, 4);
      expect(errors.single.region?.startColumn, 23);
    });

    test('a comment that a tab starts', () async {
      final SkillContext context = _context(
        _skill('name: demo-skill\ndescription: Fix bugs.\t# TODO: say when'),
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors, hasLength(1));
      expect(errors.single.subject, '# TODO: say when');
      expect(errors.single.message, endsWith('Cutoff: Fix bugs.|HERE|\t# TODO: say when'));
    });

    test('a comment in a file with CRLF line endings, without the CR', () async {
      final SkillContext context = _context(
        '---\r\nname: demo-skill\r\ndescription: Fix bugs. Use "fix #1".\r\nlicense: MIT\r\n---\r\n',
      );

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors, hasLength(1));
      expect(errors.single.subject, '#1".');
      expect(errors.single.message, endsWith('Cutoff: Fix bugs. Use "fix|HERE| #1".'));
    });

    test('an excerpt of a long description with 40 characters of context', () async {
      final String head = 'a' * 100;
      final String tail = 'b' * 100;
      final SkillContext context = _context(_skill('name: demo-skill\ndescription: $head #$tail'));

      final List<ValidationError> errors = await rule.validate(context);

      expect(errors.single.message, endsWith('Cutoff: ...${'a' * 40}|HERE| #${'b' * 38}...'));
    });
  });

  group('DescriptionYamlCommentRule passes', () {
    final passing = <String, String>{
      'a double-quoted description containing " #"':
          r'description: "Fix bugs. Use when asked \"fix #123\"."',
      'a single-quoted description containing " #"':
          "description: 'Fix bugs. Use when asked to fix #123.'",
      'a block-scalar description containing " #"':
          'description: >-\n  Fix bugs.\n  Use when asked "fix #123".',
      'a "#" with no whitespace before it':
          'description: Fix bugs. Use for owner/repo#123 and C# code.',
      'an unquoted description followed by trailing whitespace': 'description: Fix bugs.   ',
      'a comment on the line of another field': 'description: Fix bugs.\nlicense: MIT # c',
      'a description with no value, which valid-yaml-metadata reports': 'description: # TODO',
    };

    for (final MapEntry(key: String name, value: String description) in passing.entries) {
      test(name, () async {
        final SkillContext context = _context(_skill('name: demo-skill\n$description'));

        expect(await rule.validate(context), isEmpty, reason: description);
      });
    }

    test('a SKILL.md without frontmatter', () async {
      expect(await rule.validate(_context('# No frontmatter\n')), isEmpty);
    });

    test('frontmatter without a description', () async {
      expect(await rule.validate(_context(_skill('name: demo-skill'))), isEmpty);
    });

    test('frontmatter that the context does not locate in the file', () async {
      final context = SkillContext(
        directory: Directory('demo-skill'),
        rawContent: '',
        parsedYaml: loadYaml('description: Fix bugs. Use "fix #1".') as YamlMap,
      );

      expect(await rule.validate(context), isEmpty);
    });
  });

  group('registration', () {
    test('is disabled by default, per the rule-stability policy', () {
      final CheckType check = RuleRegistry.allChecks.singleWhere(
        (CheckType c) => c.name == DescriptionYamlCommentRule.ruleName,
      );

      expect(check.defaultSeverity, AnalysisSeverity.disabled);
      expect(DescriptionYamlCommentRule().severity, AnalysisSeverity.disabled);
    });

    test('RuleRegistry.createRule passes the severity to the rule', () {
      final SkillRule? rule = RuleRegistry.createRule(
        DescriptionYamlCommentRule.ruleName,
        AnalysisSeverity.warning,
      );

      expect(
        rule,
        isA<DescriptionYamlCommentRule>().having(
          (r) => r.severity,
          'severity',
          AnalysisSeverity.warning,
        ),
      );
    });
  });

  defineCliTests();
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  group('CLI $_flag', () {
    late Directory tempDir;
    late String skillPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('description_yaml_comment_test.');
      final Directory skillDir = await Directory(p.join(tempDir.path, 'skill-name')).create();
      skillPath = skillDir.path;
      await File(p.join(skillPath, 'SKILL.md')).writeAsString(
        '${buildFrontmatter(name: 'skill-name', description: 'Fix bugs. Use when asked "fix #123".')}'
        'Body\n',
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<TestProcess> run(List<String> args) {
      return startCli(['-s', skillPath, ...args], workingDirectory: tempDir.path);
    }

    test('--help lists the flag', () async {
      final TestProcess process = await startCli(['--help']);

      await process.shouldExit(0);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      expect(stdout, contains('--[no-]${DescriptionYamlCommentRule.ruleName}'));
    });

    test('passes a cut-short description without the flag', () async {
      final TestProcess process = await run([]);
      await process.shouldExit(0);
    });

    test('flag reports a cut-short description as an error', () async {
      final TestProcess process = await run([_flag]);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(
        stderr,
        contains(
          'Description field is cut short by a YAML comment. In an unquoted value, '
          '" #" starts a comment, so the description ends at |HERE| (line 3, column 44). '
          'Quote the value (description: "...") or use a block scalar (description: >-). '
          'Cutoff: Fix bugs. Use when asked "fix|HERE| #123".',
        ),
      );
    });

    test('yaml config enables the rule', () async {
      await File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
skills_lint:
  rules:
    ${DescriptionYamlCommentRule.ruleName}: error
''');

      final TestProcess process = await run([]);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('Description field is cut short by a YAML comment.'));
    });

    test('--no- flag overrides yaml config', () async {
      await File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
skills_lint:
  rules:
    ${DescriptionYamlCommentRule.ruleName}: error
''');

      final TestProcess process = await run(['--no-${DescriptionYamlCommentRule.ruleName}']);
      await process.shouldExit(0);
    });
  });
}
