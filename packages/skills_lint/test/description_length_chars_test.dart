// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/description_length_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

const _specUrl = 'https://agentskills.io/specification#description-field';

SkillContext _contextWithDescription(String description) {
  final content = '${buildFrontmatter(name: 'skill-name', description: description)}Body\n';
  final RegExpMatch? match = SkillContext.skillStartRegex.firstMatch(content);
  return SkillContext(
    directory: Directory('skill-name'),
    rawContent: content,
    parsedYaml: loadYaml(match!.group(1)!) as YamlMap?,
  );
}

Future<List<ValidationError>> _validate(DescriptionLengthRule rule, int length) {
  return rule.validate(_contextWithDescription('a' * length));
}

void main() {
  group('DescriptionLengthRule chars limit', () {
    test('defaults to the 1024 character specification limit', () async {
      final rule = DescriptionLengthRule();

      expect(rule.maxChars, 1024);
      expect(DescriptionLengthRule.defaultMaxChars, 1024);
      expect(await _validate(rule, 1024), isEmpty);
      expect(await _validate(rule, 1025), hasLength(1));
    });

    test('default diagnostic keeps the specification wording and link', () async {
      final List<ValidationError> errors = await _validate(DescriptionLengthRule(), 1120);

      expect(
        errors.single.message,
        startsWith('Description field is 1120 characters; maximum is 1024.'),
      );
      expect(errors.single.message, contains('Cutoff at character 1024:'));
      expect(errors.single.message, endsWith('(see $_specUrl)'));
      expect(errors.single.message, isNot(contains('configured')));
      expect(
        errors.single.markdownMessage,
        startsWith('**Frontmatter `description` exceeds maximum allowed length.**'),
      );
      expect(errors.single.markdownMessage, contains('over the **1024** limit)'));
      expect(errors.single.markdownMessage, contains(_specUrl));
      expect(errors.single.markdownMessage, isNot(contains('configured')));
    });

    test('a description of exactly maxChars passes and maxChars + 1 fails', () async {
      final rule = DescriptionLengthRule(maxChars: 500);

      expect(await _validate(rule, 500), isEmpty);
      expect(await _validate(rule, 501), hasLength(1));
    });

    test('a limit below 1024 reports the configured maximum without the spec link', () async {
      final List<ValidationError> errors = await _validate(
        DescriptionLengthRule(maxChars: 500),
        620,
      );

      final String message = errors.single.message;
      expect(
        message,
        startsWith('Description field is 620 characters; configured maximum is 500.'),
      );
      expect(message, contains('Cutoff at character 500:'));
      expect(message, contains('|HERE|'));
      expect(message, isNot(contains('agentskills.io')));
      expect(errors.single.markdownMessage, isNot(contains('agentskills.io')));
      expect(errors.single.markdownMessage, contains('configured'));
    });

    test('a limit of 1023 is the highest that uses the configured wording', () async {
      final List<ValidationError> errors = await _validate(
        DescriptionLengthRule(maxChars: 1023),
        1024,
      );

      expect(errors.single.message, contains('configured maximum is 1023.'));
      expect(errors.single.message, isNot(contains('agentskills.io')));
      expect(
        errors.single.markdownMessage,
        startsWith('**Frontmatter `description` exceeds configured maximum length.**'),
      );
      expect(errors.single.markdownMessage, isNot(contains('agentskills.io')));
    });

    test('a limit of exactly 1024 uses the spec wording', () async {
      final List<ValidationError> errors = await _validate(
        // Explicit so the boundary stays pinned if the default changes.
        // ignore: avoid_redundant_argument_values
        DescriptionLengthRule(maxChars: 1024),
        1025,
      );

      expect(errors.single.message, contains('; maximum is 1024.'));
      expect(errors.single.message, endsWith('(see $_specUrl)'));
    });

    test('a limit of 1024 or higher reports the spec wording with the link', () async {
      final List<ValidationError> errors = await _validate(
        DescriptionLengthRule(maxChars: 2000),
        2001,
      );

      final String message = errors.single.message;
      expect(message, startsWith('Description field is 2001 characters; maximum is 2000.'));
      expect(message, endsWith('(see $_specUrl)'));
      expect(errors.single.markdownMessage, contains(_specUrl));
    });

    test('rejects a non-positive limit', () {
      expect(() => DescriptionLengthRule(maxChars: 0), throwsArgumentError);
      expect(() => DescriptionLengthRule(maxChars: -5), throwsArgumentError);
    });
  });

  group('RuleRegistry.createRule for description-too-long', () {
    test('uses the default limit when no chars parameter is configured', () {
      final SkillRule? rule = RuleRegistry.createRule(
        DescriptionLengthRule.ruleName,
        AnalysisSeverity.error,
      );

      expect(rule, isA<DescriptionLengthRule>().having((r) => r.maxChars, 'maxChars', 1024));
    });

    test('passes the chars parameter to the rule', () {
      final SkillRule? rule = RuleRegistry.createRule(
        DescriptionLengthRule.ruleName,
        AnalysisSeverity.warning,
        CustomRuleParameters(const {DescriptionLengthRule.charsParameter: 500}),
      );

      expect(
        rule,
        isA<DescriptionLengthRule>()
            .having((r) => r.maxChars, 'maxChars', 500)
            .having((r) => r.severity, 'severity', AnalysisSeverity.warning),
      );
    });

    test('rejects a non-integer chars parameter supplied through the API', () {
      expect(
        () => RuleRegistry.createRule(
          DescriptionLengthRule.ruleName,
          AnalysisSeverity.error,
          CustomRuleParameters(const {DescriptionLengthRule.charsParameter: '500'}),
        ),
        throwsArgumentError,
      );
    });
  });

  group('skills_lint.yaml chars parameter', () {
    Configuration parseRule(String ruleYaml) {
      return ConfigParser.parse('''
skills_lint:
  rules:
    description-too-long:
$ruleYaml
''');
    }

    test('accepts a positive integer', () {
      final Configuration config = parseRule('      severity: warning\n      chars: 500');

      expect(config.parsingErrors, isEmpty);
      final RuleConfigPatch? patch = config.ruleConfigs[DescriptionLengthRule.ruleName];
      expect(patch?.severity, AnalysisSeverity.warning);
      expect(patch?.parameters?[DescriptionLengthRule.charsParameter], 500);
    });

    for (final invalid in ['0', '-5', '"500"', '12.5', 'abc']) {
      test('reports a configuration error for chars: $invalid', () {
        final Configuration config = parseRule('      chars: $invalid');

        expect(
          config.parsingErrors,
          contains(
            allOf(
              contains('"chars"'),
              contains('description-too-long'),
              contains('positive integer'),
            ),
          ),
        );
      });
    }
  });

  group('CLI --description-too-long-chars', () {
    late Directory tempDir;
    late String skillPath;
    final String binPath = p.normalize(p.absolute('bin/skills_lint.dart'));

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('description_chars_test.');
      final Directory skillDir = await Directory(p.join(tempDir.path, 'skill-name')).create();
      skillPath = skillDir.path;
      await File(
        p.join(skillPath, 'SKILL.md'),
      ).writeAsString('${buildFrontmatter(name: 'skill-name', description: 'a' * 600)}Body\n');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> writeConfig(String rule) {
      return File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
skills_lint:
  rules:
    description-too-long:
$rule
''');
    }

    Future<TestProcess> run(List<String> args) {
      return TestProcess.start('dart', [
        binPath,
        '-s',
        skillPath,
        ...args,
      ], workingDirectory: tempDir.path);
    }

    test('passes a 600 character description with the default limit', () async {
      final TestProcess process = await run([]);
      await process.shouldExit(0);
    });

    test('flag lowers the limit and uses the configured wording', () async {
      final TestProcess process = await run(['--description-too-long-chars=500']);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('Description field is 600 characters; configured maximum is 500.'));
      expect(stderr, isNot(contains('agentskills.io')));
    });

    test('flag at exactly the description length passes', () async {
      final TestProcess process = await run(['--description-too-long-chars=600']);
      await process.shouldExit(0);
    });

    test('yaml chars lowers the limit', () async {
      await writeConfig('      severity: error\n      chars: 500');

      final TestProcess process = await run([]);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('configured maximum is 500'));
    });

    test('flag overrides yaml chars', () async {
      await writeConfig('      severity: error\n      chars: 500');

      final TestProcess process = await run(['--description-too-long-chars=700']);
      await process.shouldExit(0);
    });

    test('flag overrides yaml chars in the stricter direction', () async {
      await writeConfig('      severity: error\n      chars: 700');

      final TestProcess process = await run(['--description-too-long-chars=550']);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('configured maximum is 550'));
    });

    for (final invalid in ['0', '-1', 'abc', '12.5']) {
      test('rejects --description-too-long-chars=$invalid as bad usage', () async {
        final TestProcess process = await run(['--description-too-long-chars=$invalid']);

        await process.shouldExit(64);
        final String stderr = (await process.stderr.rest.toList()).join('\n');
        expect(stderr, contains('description-too-long-chars'));
        expect(stderr, contains('positive integer'));
      });
    }

    test('rejects invalid yaml chars with a configuration error', () async {
      await writeConfig('      chars: 0');

      final TestProcess process = await run([]);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('Configuration error'));
      expect(stderr, contains('positive integer'));
    });
  });
}
