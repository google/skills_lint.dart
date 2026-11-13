// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/fix_outcome.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/skill_naming_rule.dart';
import 'package:skills_lint/src/skill_fixer.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('SkillNamingRule', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('skill_naming_rule_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<List<ValidationError>> validateName(
      String skillName, {
      String? prefix,
      int? maxLength,
      AnalysisSeverity severity = AnalysisSeverity.error,
    }) {
      final rule = SkillNamingRule(severity: severity, prefix: prefix, maxLength: maxLength);
      return rule.validate(
        createTestSkillContext(directory: Directory(p.join(tempDir.path, skillName))),
      );
    }

    group('prefix', () {
      test('accepts a name that equals the prefix', () async {
        expect(await validateName('myproject', prefix: 'myproject'), isEmpty);
      });

      test('accepts a name that starts with the prefix and a hyphen', () async {
        expect(await validateName('myproject-setup', prefix: 'myproject'), isEmpty);
      });

      test('reports a name without the prefix and suggests a name', () async {
        final List<ValidationError> errors = await validateName('my-foobar', prefix: 'myproject');

        expect(errors, hasLength(1));
        final ValidationError error = errors.single;
        expect(error.ruleId, SkillNamingRule.ruleName);
        expect(error.severity, AnalysisSeverity.error);
        expect(
          error.message,
          'Skill "my-foobar" must be "myproject" or start with "myproject-". '
          'Suggested name: "myproject-my-foobar".\n'
          'Fix by re-running your validation command with `--fix`.',
        );
        expect(error.markdownMessage, contains('* **Suggested:** `myproject-my-foobar`'));
        expect(error.region?.startLine, 2);
      });

      test('reports a name that starts with the prefix but no hyphen', () async {
        final List<ValidationError> errors = await validateName('myprojectx', prefix: 'myproject');

        expect(errors.single.message, contains('Suggested name: "myproject-myprojectx"'));
      });

      test('reports a name that has the prefix in uppercase', () async {
        final List<ValidationError> errors = await validateName('MyProject-x', prefix: 'myproject');

        expect(errors.single.message, contains('Suggested name: "myproject-x"'));
      });

      test('says --fix skips a suggested name longer than the max-length', () async {
        final List<ValidationError> errors = await validateName(
          'my-foobar',
          prefix: 'myproject',
          maxLength: 15,
        );

        expect(
          errors.single.message,
          'Skill "my-foobar" must be "myproject" or start with "myproject-". '
          'Rename it by hand to at most 15 characters. `--fix` skips this rename, '
          'because "myproject-my-foobar" is longer than the max-length.',
        );
        expect(errors.single.markdownMessage, isNot(contains('name: myproject-my-foobar')));
      });
    });

    group('max-length', () {
      test('accepts a name of exactly the max-length', () async {
        expect(await validateName('my-skill', maxLength: 8), isEmpty);
      });

      test('reports a name longer than the max-length', () async {
        final List<ValidationError> errors = await validateName('my-long-skill', maxLength: 8);

        expect(errors, hasLength(1));
        expect(
          errors.single.message,
          'Skill "my-long-skill" is 13 characters; the max-length is 8. '
          'Shorten the `name:` field in SKILL.md.',
        );
        expect(errors.single.region?.startLine, 2);
      });

      test('reports both conventions when a name breaks both', () async {
        final List<ValidationError> errors = await validateName(
          'my-long-skill',
          prefix: 'myproject',
          maxLength: 8,
        );

        expect(errors.map((e) => e.message), [
          startsWith('Skill "my-long-skill" must be "myproject"'),
          startsWith('Skill "my-long-skill" is 13 characters'),
        ]);
      });
    });

    test('reports each skill when no parameter is set', () async {
      for (final String? prefix in [null, '']) {
        final List<ValidationError> errors = await validateName('my-foobar', prefix: prefix);

        expect(errors, hasLength(1), reason: 'prefix: $prefix');
        expect(
          errors.single.message,
          'The skill-naming rule has no convention to check. Set its prefix or max-length '
          'parameter in skills_lint.yaml or pass --skill-naming-prefix or '
          '--skill-naming-max-length, or disable the rule.',
        );
        expect(errors.single.region?.startLine, 2);
      }
    });

    test('reports at the configured severity', () async {
      final List<ValidationError> errors = await validateName(
        'my-foobar',
        prefix: 'myproject',
        severity: AnalysisSeverity.warning,
      );

      expect(errors.single.severity, AnalysisSeverity.warning);
    });

    test('reports nothing when the frontmatter has no name', () async {
      final rule = SkillNamingRule(severity: AnalysisSeverity.error);
      final SkillContext context = createTestSkillContext(
        directory: tempDir,
        rawContent: '---\ndescription: Test\n---\n',
      );

      expect(await rule.validate(context), isEmpty);
    });

    group('fix', () {
      Map<String, RuleConfig> namingConfig(Map<String, Object> parameters) => {
        SkillNamingRule.ruleName: RuleConfig(
          severity: AnalysisSeverity.error,
          parameters: CustomRuleParameters(parameters),
        ),
      };

      Future<FixOutcome> fixSkill(String skillName, Map<String, RuleConfig> ruleConfigs) async {
        final Directory skillDir = await createDummySkill(
          tempDir,
          name: skillName,
          skillContent: buildFrontmatter(name: skillName),
        );
        final validator = Validator(ruleConfigs: ruleConfigs);
        return SkillFixer(
          validator: validator,
          applyIgnores: (_) {},
          onFixFailed: (ruleName, error) => fail('$ruleName fix threw $error'),
        ).fix(await validator.validate(skillDir));
      }

      test('renames the skill and its directory to the suggested name', () async {
        final FixOutcome outcome = await fixSkill(
          'my-foobar',
          namingConfig({SkillNamingRule.prefixParameter: 'myproject'}),
        );

        expect(outcome.content, contains('name: myproject-my-foobar\n'));
        expect(outcome.directoryName, 'myproject-my-foobar');
        expect(outcome.result.validationErrors, isEmpty);
      });

      test('leaves a name with the prefix unchanged', () async {
        final FixOutcome outcome = await fixSkill(
          'myproject-setup',
          namingConfig({SkillNamingRule.prefixParameter: 'myproject'}),
        );

        expect(outcome.directoryName, 'myproject-setup');
        expect(outcome.result.validationErrors, isEmpty);
      });

      test('skips a rename to a name longer than the max-length', () async {
        final rule = SkillNamingRule(
          severity: AnalysisSeverity.error,
          prefix: 'myproject',
          maxLength: 15,
        );
        final String content = buildFrontmatter(name: 'my-foobar');

        expect(await rule.fix(SkillContext(directory: tempDir, rawContent: content)), content);
      });

      test('leaves a name longer than the max-length unchanged', () async {
        final FixOutcome outcome = await fixSkill(
          'my-long-skill',
          namingConfig({SkillNamingRule.maxLengthParameter: 8}),
        );

        expect(outcome.directoryName, 'my-long-skill');
        expect(outcome.appliedRuleNames, isEmpty);
      });

      test('leaves the skill unchanged when no prefix is set', () async {
        final rule = SkillNamingRule(severity: AnalysisSeverity.error, maxLength: 8);
        final String content = buildFrontmatter(name: 'my-long-skill');

        expect(await rule.fix(SkillContext(directory: tempDir, rawContent: content)), content);
      });
    });
  });
}
