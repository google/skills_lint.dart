// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/parameter_constraint.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/rule_parameter_type.dart';
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
const String _param = DescriptionLengthRule.maxDescriptionLengthParameter;
const String _flag = '--description-too-long-$_param';

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
  test('parameter name is namespaced to the description length', () {
    expect(_param, 'description-length-max');
    expect(_flag, '--description-too-long-description-length-max');
  });

  group('DescriptionLengthRule limit', () {
    test('defaults to the 1024 character specification limit', () async {
      final rule = DescriptionLengthRule();

      expect(rule.maxLength, DescriptionLengthRule.maxDescriptionLength);
      expect(DescriptionLengthRule.maxDescriptionLength, 1024);
      expect(await _validate(rule, 1024), isEmpty);
      expect(await _validate(rule, 1025), hasLength(1));
    });

    test('a description of exactly maxLength passes and maxLength + 1 fails', () async {
      final rule = DescriptionLengthRule(maxLength: 500);

      expect(await _validate(rule, 500), isEmpty);
      expect(await _validate(rule, 501), hasLength(1));
    });
  });

  group('diagnostic when the limit equals the specification maximum', () {
    test('uses the specification wording and link', () async {
      final ValidationError error = (await _validate(DescriptionLengthRule(), 1120)).single;

      expect(
        error.message,
        startsWith('Description field is 1120 characters; maximum is 1024. Cutoff: ...'),
      );
      expect(error.message, endsWith('(see $_specUrl)'));
      expect(error.message, isNot(contains('configured')));
      expect(
        error.markdownMessage,
        startsWith(
          '**Frontmatter `description` exceeds maximum allowed length.**\n\n'
          '**1120** characters (**96** characters over the **1024** limit).\n\n'
          '**Cutoff excerpt:**\n> ...',
        ),
      );
      expect(error.markdownMessage, endsWith('*(See [Agent Skills Specification]($_specUrl))*'));
      expect(error.markdownMessage, isNot(contains('configured')));
    });
  });

  group('diagnostic when the limit is below the specification maximum', () {
    test('reports the configured maximum without the spec link', () async {
      final ValidationError error = (await _validate(
        DescriptionLengthRule(maxLength: 500),
        620,
      )).single;

      expect(
        error.message,
        startsWith('Description field is 620 characters; configured maximum is 500. Cutoff: ...'),
      );
      expect(error.message, endsWith('...'));
      expect(error.message, isNot(contains('agentskills.io')));
      expect(
        error.markdownMessage,
        startsWith(
          '**Frontmatter `description` exceeds configured maximum length.**\n\n'
          '**620** characters (**120** characters over the configured **500** limit).\n\n'
          '**Cutoff excerpt:**\n> ...',
        ),
      );
      expect(error.markdownMessage, isNot(contains('agentskills.io')));
    });

    test('1023 is the highest limit that omits the spec link', () async {
      final ValidationError error = (await _validate(
        DescriptionLengthRule(maxLength: 1023),
        1024,
      )).single;

      expect(error.message, contains('configured maximum is 1023.'));
      expect(error.message, isNot(contains('agentskills.io')));
    });
  });

  group('diagnostic when the limit is above the specification maximum', () {
    test('reports the configured maximum, the spec maximum, and the spec link', () async {
      final ValidationError error = (await _validate(
        DescriptionLengthRule(maxLength: 2000),
        2100,
      )).single;

      expect(
        error.message,
        startsWith(
          'Description field is 2100 characters; configured maximum is 2000 '
          '(specification maximum is 1024). Cutoff: ...',
        ),
      );
      expect(error.message, endsWith('(see $_specUrl)'));
      expect(
        error.markdownMessage,
        startsWith(
          '**Frontmatter `description` exceeds configured maximum length.**\n\n'
          '**2100** characters (**100** characters over the configured **2000** limit; '
          'the specification maximum is **1024**).\n\n'
          '**Cutoff excerpt:**\n> ...',
        ),
      );
      expect(error.markdownMessage, endsWith('*(See [Agent Skills Specification]($_specUrl))*'));
    });

    test('1025 is the lowest limit that names the spec maximum', () async {
      final ValidationError error = (await _validate(
        DescriptionLengthRule(maxLength: 1025),
        1026,
      )).single;

      expect(
        error.message,
        contains('configured maximum is 1025 (specification maximum is 1024).'),
      );
    });
  });

  group('ParameterConstraint.positiveInteger', () {
    test('accepts integers of at least 1', () {
      expect(ParameterConstraint.positiveInteger.accepts(1), isTrue);
      expect(ParameterConstraint.positiveInteger.accepts(2000), isTrue);
    });

    test('rejects zero, negative numbers, and non-integers', () {
      for (final Object value in [0, -1, 1.5, '1']) {
        expect(ParameterConstraint.positiveInteger.accepts(value), isFalse, reason: '$value');
      }
    });

    test('describes the accepted values', () {
      expect(ParameterConstraint.positiveInteger.description, 'a positive integer');
    });
  });

  group('CheckType parameter constraints', () {
    const check = CheckType(
      name: 'mock-rule',
      defaultSeverity: AnalysisSeverity.disabled,
      help: 'Mock rule.',
      parameterSchema: {'count': RuleParameterType.integer},
      parameterConstraints: {'count': ParameterConstraint.positiveInteger},
    );

    test('accept values that meet the constraint', () {
      expect(check.validateParameters(CustomRuleParameters(const {'count': 1})), isEmpty);
    });

    test('reject values that break the constraint with the accepted values', () {
      const expected =
          'Invalid value for parameter "count" in rule "mock-rule". '
          'Expected a positive integer, got "0".';
      expect(check.validateParameters(CustomRuleParameters(const {'count': 0})), [expected]);
    });

    test('report a type mismatch without checking the constraint', () {
      expect(check.validateParameters(CustomRuleParameters(const {'count': 'x'})), [
        'Invalid value/type for parameter "count" in rule "mock-rule". Expected int, got "x".',
      ]);
    });

    test('skip null values, which clear a parameter', () {
      expect(check.validateParameters(CustomRuleParameters(const {'count': null})), isEmpty);
    });
  });

  group('RuleRegistry.createRule for description-too-long', () {
    test('uses the specification maximum when the parameter is not configured', () {
      final SkillRule? rule = RuleRegistry.createRule(
        DescriptionLengthRule.ruleName,
        AnalysisSeverity.error,
      );

      expect(rule, isA<DescriptionLengthRule>().having((r) => r.maxLength, 'maxLength', 1024));
    });

    test('passes the configured limit to the rule', () {
      final SkillRule? rule = RuleRegistry.createRule(
        DescriptionLengthRule.ruleName,
        AnalysisSeverity.warning,
        CustomRuleParameters(const {_param: 500}),
      );

      expect(
        rule,
        isA<DescriptionLengthRule>()
            .having((r) => r.maxLength, 'maxLength', 500)
            .having((r) => r.severity, 'severity', AnalysisSeverity.warning),
      );
    });

    for (final Object invalid in ['500', 0, -5]) {
      test('rejects $invalid supplied through the Dart API', () {
        expect(
          () => RuleRegistry.createRule(
            DescriptionLengthRule.ruleName,
            AnalysisSeverity.error,
            CustomRuleParameters({_param: invalid}),
          ),
          throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains(_param))),
        );
      });
    }
  });

  group('skills_lint.yaml $_param parameter', () {
    Configuration parseRule(String ruleYaml) {
      return ConfigParser.parse('''
skills_lint:
  rules:
    description-too-long:
$ruleYaml
''');
    }

    test('accepts a positive integer', () {
      final Configuration config = parseRule('      severity: warning\n      $_param: 500');

      expect(config.parsingErrors, isEmpty);
      final RuleConfigPatch? patch = config.ruleConfigs[DescriptionLengthRule.ruleName];
      expect(patch?.severity, AnalysisSeverity.warning);
      expect(patch?.parameters?[_param], 500);
    });

    for (final invalid in ['0', '-5']) {
      test('reports a configuration error for $_param: $invalid', () {
        final Configuration config = parseRule('      $_param: $invalid');

        expect(config.parsingErrors, [
          contains(
            'Invalid value for parameter "$_param" in rule "description-too-long". '
            'Expected a positive integer, got "$invalid".',
          ),
        ]);
      });
    }

    for (final invalid in ['"500"', '12.5', 'abc']) {
      test('reports a type error for $_param: $invalid', () {
        final Configuration config = parseRule('      $_param: $invalid');

        expect(config.parsingErrors, [contains('Expected int')]);
      });
    }
  });

  group('CLI $_flag', () {
    late Directory tempDir;
    late String skillPath;
    final String binPath = p.normalize(p.absolute('bin/skills_lint.dart'));

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('description_limit_test.');
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
      final TestProcess process = await run(['$_flag=500']);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('Description field is 600 characters; configured maximum is 500.'));
      expect(stderr, isNot(contains('agentskills.io')));
    });

    test('flag at exactly the description length passes', () async {
      final TestProcess process = await run(['$_flag=600']);
      await process.shouldExit(0);
    });

    test('yaml lowers the limit', () async {
      await writeConfig('      severity: error\n      $_param: 500');

      final TestProcess process = await run([]);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('configured maximum is 500'));
    });

    test('flag overrides yaml', () async {
      await writeConfig('      severity: error\n      $_param: 500');

      final TestProcess process = await run(['$_flag=700']);
      await process.shouldExit(0);
    });

    test('flag overrides yaml in the stricter direction', () async {
      await writeConfig('      severity: error\n      $_param: 700');

      final TestProcess process = await run(['$_flag=550']);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('configured maximum is 550'));
    });

    for (final invalid in ['0', '-1']) {
      test('rejects $_flag=$invalid as bad usage', () async {
        final TestProcess process = await run(['$_flag=$invalid']);

        await process.shouldExit(64);
        final String stderr = (await process.stderr.rest.toList()).join('\n');
        expect(
          stderr,
          contains(
            'Invalid value for parameter "$_param" in rule "description-too-long". '
            'Expected a positive integer, got "$invalid".',
          ),
        );
      });
    }

    for (final invalid in ['abc', '12.5']) {
      test('rejects $_flag=$invalid as bad usage', () async {
        final TestProcess process = await run(['$_flag=$invalid']);

        await process.shouldExit(64);
        final String stderr = (await process.stderr.rest.toList()).join('\n');
        expect(stderr, contains('Expected an integer'));
      });
    }

    test('rejects invalid yaml with a configuration error', () async {
      await writeConfig('      $_param: 0');

      final TestProcess process = await run([]);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('Configuration error'));
      expect(stderr, contains('Expected a positive integer'));
    });
  });
}
