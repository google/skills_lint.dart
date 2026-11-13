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
import 'package:skills_lint/src/rules/skill_name_prefix_rule.dart';
import 'package:skills_lint/src/skill_fixer.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('SkillNamePrefixRule', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('skill_name_prefix_rule_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<List<ValidationError>> validateName(String skillName, {String? prefix}) {
      final rule = SkillNamePrefixRule(severity: AnalysisSeverity.error, prefix: prefix);
      return rule.validate(
        createTestSkillContext(directory: Directory(p.join(tempDir.path, skillName))),
      );
    }

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
      expect(error.ruleId, SkillNamePrefixRule.ruleName);
      expect(error.severity, AnalysisSeverity.error);
      expect(
        error.message,
        'Skill "my-foobar" does not start with the prefix "myproject". '
        'Skill names must be "myproject" or start with "myproject-". '
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

    for (final String? prefix in [null, '']) {
      test('reports each skill when the prefix is ${prefix == null ? 'unset' : 'empty'}', () async {
        final List<ValidationError> errors = await validateName('my-foobar', prefix: prefix);

        expect(errors, hasLength(1));
        expect(
          errors.single.message,
          'The skill-name-prefix rule has no prefix to check. Set its '
          '${SkillNamePrefixRule.prefixParameter} parameter in skills_lint.yaml or pass '
          '--skill-name-prefix-${SkillNamePrefixRule.prefixParameter}, or disable the rule.',
        );
        expect(errors.single.region?.startLine, 2);
      });
    }

    test('reports nothing when the frontmatter has no name', () async {
      final rule = SkillNamePrefixRule(severity: AnalysisSeverity.error);
      final SkillContext context = createTestSkillContext(
        directory: tempDir,
        rawContent: '---\ndescription: Test\n---\n',
      );

      expect(await rule.validate(context), isEmpty);
    });

    group('fix', () {
      final Map<String, RuleConfig> prefixConfig = {
        SkillNamePrefixRule.ruleName: RuleConfig(
          severity: AnalysisSeverity.error,
          parameters: CustomRuleParameters(const {
            SkillNamePrefixRule.prefixParameter: 'myproject',
          }),
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
        final FixOutcome outcome = await fixSkill('my-foobar', prefixConfig);

        expect(outcome.content, contains('name: myproject-my-foobar\n'));
        expect(outcome.directoryName, 'myproject-my-foobar');
        expect(outcome.result.validationErrors, isEmpty);
      });

      test('leaves a name with the prefix unchanged', () async {
        final FixOutcome outcome = await fixSkill('myproject-setup', prefixConfig);

        expect(outcome.directoryName, 'myproject-setup');
        expect(outcome.result.validationErrors, isEmpty);
      });

      test('leaves the skill unchanged when the prefix is unset', () async {
        final rule = SkillNamePrefixRule(severity: AnalysisSeverity.error);
        final String content = buildFrontmatter(name: 'my-foobar');

        expect(await rule.fix(SkillContext(directory: tempDir, rawContent: content)), content);
      });
    });
  });
}
