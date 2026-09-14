// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/skills_lint.dart';
import 'package:skills_lint/src/rules/absolute_paths_rule.dart';
import 'package:skills_lint/src/rules/name_format_rule.dart';
import 'package:skills_lint/src/rules/path_does_not_exist_rule.dart';
import 'package:skills_lint/src/rules/prevent_skills_sh_publishing_rule.dart';
import 'package:skills_lint/src/rules/published_skill_name_rule.dart';
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:skills_lint/src/rules/trailing_whitespace_rule.dart';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

void main() {
  group('Configuration File Integration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('config_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('obeys disabled relative paths in config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
[broken](missing.md)''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          ruleConfigs: {
            RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
          },
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('Skill is valid.'));
      await process.shouldExit(0);
    });

    test('obeys warning absolute paths in config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
[absolute](/absolute/path.md)''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          ruleConfigs: {
            AbsolutePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
          },
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('Warnings:'));
      await process.shouldExit(0);
    });

    test('obeys path-specific rules with tilde in config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Line with 1 space 
'''); // Trailing space

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          directoryConfigs: [
            LintTargetConfig(
              path: '~/test-skill',
              ruleConfigs: {
                TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              },
            ),
          ],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start(
        'dart',
        [p.normalize(p.absolute('bin/skills_lint.dart')), '-s', '~/test-skill'],
        environment: {'HOME': tempDir.path},
        workingDirectory: tempDir.path,
      );

      final List<String> stderr = await process.stderr.rest.toList();
      expect(stderr.join('\n'), contains('has 1 trailing space(s)'));
      await process.shouldExit(1);
    });

    test('CLI flags override path-specific config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Line with 1 space 
'''); // Trailing space

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          directoryConfigs: [
            LintTargetConfig(
              path: 'test-skill',
              ruleConfigs: {
                TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              },
            ),
          ],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--no-check-trailing-whitespace',
      ], workingDirectory: tempDir.path);

      await process.shouldExit(0);
    });

    test('obeys individual_skills block in config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Line with 1 space 
'''); // Trailing space

      // Create a second skill not listed in the config to act as a negative test.
      // This ensures the rule is applied strictly to `test-skill` and hasn't accidentally bled globally.
      final Directory otherSkillDir = await Directory('${tempDir.path}/other-skill').create();
      await File('${otherSkillDir.path}/SKILL.md').writeAsString('''
---
name: other-skill
description: Another test skill
---
Line with 1 space 
'''); // Trailing space

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          individualSkillConfigs: [
            LintTargetConfig(
              path: 'test-skill',
              ruleConfigs: {
                TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              },
            ),
          ],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '-s',
        'other-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      final String output = stderr.join('\n');
      expect(output, contains('has 1 trailing space(s)'));
      expect(output, isNot(contains('other-skill')));
      await process.shouldExit(1);
    });

    test('succeeds on non-overlapping individual_skills and directories paths', () async {
      await Directory('${tempDir.path}/dir1').create();
      await File('${tempDir.path}/dir1/SKILL.md').writeAsString('''
---
name: dir1
description: A test skill
---
Body''');

      await Directory('${tempDir.path}/dir2').create();
      await File('${tempDir.path}/dir2/SKILL.md').writeAsString('''
---
name: dir2
description: A test skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          directoryConfigs: [LintTargetConfig(path: 'dir1')],
          individualSkillConfigs: [LintTargetConfig(path: 'dir2')],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
      ], workingDirectory: tempDir.path);

      await process.shouldExit(0);
    });

    test('CLI flags override config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
[broken](missing.md)''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          ruleConfigs: {
            RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
          },
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--check-relative-paths',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(stderr.join('\n'), contains('Skill is invalid:'));
      await process.shouldExit(1);
    });

    test('writes empty ignore-file if missing and specified in config', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      const ignorePath = 'custom_ignore.json';
      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          directoryConfigs: [LintTargetConfig(path: 'test-skill', ignoreFile: ignorePath)],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('File not found generating-baseline'));
      await process.shouldExit(0);

      final writtenFile = File('${tempDir.path}/$ignorePath');
      expect(writtenFile.existsSync(), isTrue);
      final String fileContent = await writtenFile.readAsString();
      expect(fileContent, contains('"skills":'));
    });

    test('ignores config when --ignore-config is passed', () async {
      final Directory skillDir = await Directory('${tempDir.path}/TEST-SKILL').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: TEST-SKILL
description: A test skill
license: MIT
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          ruleConfigs: {
            NameFormatRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
          },
        ).toYamlString(),
      );

      // 1. Run without --ignore-config. Should pass because config disables the check.
      final TestProcess passProcess = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'TEST-SKILL',
      ], workingDirectory: tempDir.path);
      await passProcess.shouldExit(0);

      // 2. Run with --ignore-config. Should fail because config is ignored and default is used.
      final TestProcess failProcess = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'TEST-SKILL',
        '--ignore-config',
      ], workingDirectory: tempDir.path);
      await failProcess.shouldExit(1);
    });

    test('ignores config when generating baseline with --ignore-config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/TEST-SKILL').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: TEST-SKILL
description: A test skill
license: MIT
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          ruleConfigs: {
            NameFormatRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
          },
        ).toYamlString(),
      );

      // 1. Generate baseline with --ignore-config. It should ignore config (so the rule is enabled) and find violations to generate baseline for!
      final TestProcess genProcess = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'TEST-SKILL',
        '--generate-baseline',
        '--ignore-config',
      ], workingDirectory: tempDir.path);
      await genProcess.shouldExit(0); // Exits 0 if --generate-baseline passed

      final ignoreFile = File('${skillDir.path}/$defaultIgnoreFileName');
      expect(ignoreFile.existsSync(), isTrue);

      final String content = await ignoreFile.readAsString();
      expect(content, contains(NameFormatRule.ruleName)); // It should generate baseline for it!
    });

    test('fails on invalid top-level key in config by default', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  invalid-key: value
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains('Configuration error: Unrecognized top-level key "invalid-key"'),
      );
      await process.shouldExit(1);
    });

    test('bad path: type emits parsing error and lets later entries through', () async {
      // First entry has path: 123 (not a string). Second entry is well-formed.
      // The bad-type entry should produce a parsingErrors line but must not
      // prevent the second entry from being parsed.
      await Directory('${tempDir.path}/good-skill').create();
      await File('${tempDir.path}/good-skill/SKILL.md').writeAsString('''
---
name: good-skill
description: A valid skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  directories:
    - path: 123
    - path: "good-skill"
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      final String stderrStr = stderr.join('\n');
      expect(stderrStr, contains('Configuration error: Directory entry "path" must be a string'));
      // Without the fix, the unchecked cast would throw inside the
      // top-level try/catch and 'good-skill' would never run.
      await process.shouldExit(1); // exits 1 due to parsing error
    });

    test('fails on invalid directory key in config by default', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  directories:
    - path: "test-skill"
      invalid-dir-key: value
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains('Configuration error: Unrecognized key "invalid-dir-key"'),
      );
      await process.shouldExit(1);
    });

    test('fails on unrecognized parameter key in YAML rule definition by default', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  rules:
    path-does-not-exist:
      severity: error
      invalid-parameter-key: value
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains(
          'Configuration error: Global rules: Unrecognized parameter "invalid-parameter-key" for rule "path-does-not-exist".',
        ),
      );
      await process.shouldExit(1);
    });

    test('fails on invalid parameter value type in YAML rule definition by default', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  rules:
    path-does-not-exist:
      severity: error
      exclude: 123
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains(
          'Configuration error: Global rules: Invalid value/type for parameter "exclude" in rule "path-does-not-exist". Expected RegExp (valid regular expression string), got "123".',
        ),
      );
      await process.shouldExit(1);
    });

    test(
      'succeeds with warning on invalid key and prints deprecation when --allow-misconfigured-keys passed',
      () async {
        await Directory('${tempDir.path}/test-skill').create();
        await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

        await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  invalid-key: value
''');

        final TestProcess process = await TestProcess.start('dart', [
          p.normalize(p.absolute('bin/skills_lint.dart')),
          '-s',
          'test-skill',
          '--allow-misconfigured-keys',
        ], workingDirectory: tempDir.path);

        final List<String> stdout = await process.stdout.rest.toList();
        final String output = stdout.join('\n');
        expect(output, contains('Configuration warning: Unrecognized top-level key "invalid-key"'));
        expect(output, contains('DEPRECATION WARNING: --allow-misconfigured-keys is deprecated'));
        await process.shouldExit(0);
      },
    );

    test('obeys custom configuration file path via --config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
[broken](missing.md)''');

      await File('${tempDir.path}/custom_config.yaml').writeAsString(
        const Configuration(
          ruleConfigs: {
            RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
          },
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--config',
        'custom_config.yaml',
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('Skill is valid.'));
      await process.shouldExit(0);
    });

    test('exits with 1 and prints error message if --config points to non-existent file', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--config',
        'non_existent_config.yaml',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(stderr.join('\n'), contains('Configuration file not found'));
      expect(stderr.join('\n'), contains('non_existent_config.yaml'));
      await process.shouldExit(1);
    });

    test('ignores config when both --config and --ignore-config are passed', () async {
      final Directory skillDir = await Directory('${tempDir.path}/TEST-SKILL').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: TEST-SKILL
description: A test skill
license: MIT
---
Body''');

      await File('${tempDir.path}/custom_config.yaml').writeAsString(
        const Configuration(
          ruleConfigs: {
            NameFormatRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
          },
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'TEST-SKILL',
        '--config',
        'custom_config.yaml',
        '--ignore-config',
      ], workingDirectory: tempDir.path);

      await process.shouldExit(1);
    });

    test('fails on invalid individual_skills key in config by default', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  individual_skills:
    - path: "test-skill"
      invalid-ind-key: value
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains(
          'Configuration error: Unrecognized key "invalid-ind-key" in individual skill entry for "test-skill".',
        ),
      );
      await process.shouldExit(1);
    });

    test(
      'processes both configured directories and individual skills when no arguments are passed',
      () async {
        // 1. Create a directory target with a nested skill
        await Directory('${tempDir.path}/dir-target/dir-skill').create(recursive: true);
        await File('${tempDir.path}/dir-target/dir-skill/SKILL.md').writeAsString('''
---
name: dir-skill
description: A directory skill
---
Body''');

        // 2. Create an individual skill target
        await Directory('${tempDir.path}/ind-skill').create();
        await File('${tempDir.path}/ind-skill/SKILL.md').writeAsString('''
---
name: ind-skill
description: An individual skill
---
Body''');

        await File('${tempDir.path}/skills_lint.yaml').writeAsString(
          const Configuration(
            directoryConfigs: [LintTargetConfig(path: 'dir-target')],
            individualSkillConfigs: [LintTargetConfig(path: 'ind-skill')],
          ).toYamlString(),
        );

        // Run with NO arguments (no -s or -d)
        final TestProcess process = await TestProcess.start('dart', [
          p.normalize(p.absolute('bin/skills_lint.dart')),
        ], workingDirectory: tempDir.path);

        final List<String> stdout = await process.stdout.rest.toList();
        final String output = stdout.join('\n');

        // Should validate both exactly once
        expect('Validating skill: dir-skill'.allMatches(output).length, 1);
        expect('Validating skill: ind-skill'.allMatches(output).length, 1);
        await process.shouldExit(0);
      },
    );

    test('CLI targets override configured individual_skills', () async {
      final Directory cliSkillDir = await Directory('${tempDir.path}/cli-skill').create();
      await File('${cliSkillDir.path}/SKILL.md').writeAsString('''
---
name: cli-skill
description: A test skill passed via CLI
---
Body''');

      final Directory configSkillDir = await Directory('${tempDir.path}/config-skill').create();
      await File('${configSkillDir.path}/SKILL.md').writeAsString('''
---
name: config-skill
description: A test skill in config
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          individualSkillConfigs: [LintTargetConfig(path: 'config-skill')],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'cli-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      final String output = stdout.join('\n');

      // The CLI target should be validated
      expect(output, contains('Validating skill: cli-skill'));
      // The config target should NOT be validated because the CLI target overrides it
      expect(output, isNot(contains('Validating skill: config-skill')));

      await process.shouldExit(0);
    });

    test('later config entries override earlier ones for overlapping paths', () async {
      await Directory('${tempDir.path}/dir1').create();
      await Directory('${tempDir.path}/dir1/test-skill').create();
      // Add trailing whitespace to trigger a lint rule
      await File(
        '${tempDir.path}/dir1/test-skill/SKILL.md',
      ).writeAsString('---\nname: test-skill\ndescription: A test skill\n---\nBody \n');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        const Configuration(
          directoryConfigs: [
            LintTargetConfig(
              path: 'dir1',
              ruleConfigs: {
                TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              },
            ),
          ],
          individualSkillConfigs: [
            LintTargetConfig(
              path: 'dir1/test-skill',
              ruleConfigs: {
                TrailingWhitespaceRule.ruleName: RuleConfigPatch(
                  severity: AnalysisSeverity.warning,
                ),
              },
            ),
          ],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-d',
        'dir1',
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      final String output = stdout.join('\n');

      // Should show a warning, not an error. Exit code 0 for warnings.
      expect(output, contains('Warnings:'));
      expect(output, contains('Line 5 has 1 trailing space(s)'));
      await process.shouldExit(0);
    });

    test('obeys map-based rule parameters configuration', () async {
      await Directory('${tempDir.path}/skills-root').create();
      await Directory('${tempDir.path}/skills-root/definition-of-done-workspace').create();
      final Directory validSkill = await Directory(
        '${tempDir.path}/skills-root/valid-skill',
      ).create();
      await File(
        '${validSkill.path}/SKILL.md',
      ).writeAsString('---\nname: valid-skill\ndescription: Valid\n---\nBody');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        Configuration(
          directoryConfigs: [
            LintTargetConfig(
              path: 'skills-root',
              ruleConfigs: {
                PathDoesNotExistRule.ruleName: RuleConfigPatch(
                  severity: AnalysisSeverity.error,
                  parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
                ),
              },
            ),
          ],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-d',
        'skills-root',
      ], workingDirectory: tempDir.path);

      await process.shouldExit(0);
    });

    test('preserves global rule parameters when target overrides only severity', () async {
      await Directory('${tempDir.path}/skills-root').create();
      await Directory('${tempDir.path}/skills-root/definition-of-done-workspace').create();
      final Directory validSkill = await Directory(
        '${tempDir.path}/skills-root/valid-skill',
      ).create();
      await File(
        '${validSkill.path}/SKILL.md',
      ).writeAsString('---\nname: valid-skill\ndescription: Valid\n---\nBody');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString(
        Configuration(
          ruleConfigs: {
            PathDoesNotExistRule.ruleName: RuleConfigPatch(
              severity: AnalysisSeverity.warning,
              parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
            ),
          },
          directoryConfigs: const [
            LintTargetConfig(
              path: 'skills-root',
              ruleConfigs: {
                PathDoesNotExistRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              },
            ),
          ],
        ).toYamlString(),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-d',
        'skills-root',
      ], workingDirectory: tempDir.path);

      // Exits with 0 because definition-of-done-workspace is still excluded (inherited global parameters)
      await process.shouldExit(0);
    });

    test(
      'clears inherited rule parameters when target overrides key with tilde (~) null value',
      () async {
        await Directory('${tempDir.path}/skills-root').create();
        await Directory('${tempDir.path}/skills-root/definition-of-done-workspace').create();
        final Directory validSkill = await Directory(
          '${tempDir.path}/skills-root/valid-skill',
        ).create();
        await File(
          '${validSkill.path}/SKILL.md',
        ).writeAsString('---\nname: valid-skill\ndescription: Valid\n---\nBody');

        await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  rules:
    path-does-not-exist:
      severity: error
      exclude: ".*-workspace"
  directories:
    - path: "skills-root"
      rules:
        path-does-not-exist:
          exclude: ~
''');

        final TestProcess process = await TestProcess.start('dart', [
          p.normalize(p.absolute('bin/skills_lint.dart')),
          '-d',
          'skills-root',
        ], workingDirectory: tempDir.path);

        // Exits with 1 because exclude was nullified by ~, so definition-of-done-workspace is evaluated
        // and fails due to missing SKILL.md.
        await process.shouldExit(1);
      },
    );

    test('yields RuleParameterType schema validation error for nested collections', () async {
      await Directory('${tempDir.path}/test-skill').create();
      await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

      await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  rules:
    path-does-not-exist:
      severity: error
      exclude:
        - ".*-workspace"
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains(
          'Configuration error: Global rules: Invalid value/type for parameter "exclude" in rule "path-does-not-exist"',
        ),
      );
      await process.shouldExit(1);
    });

    test(
      'yields RuleParameterType schema validation error for malformed regular expression',
      () async {
        await Directory('${tempDir.path}/test-skill').create();
        await File('${tempDir.path}/test-skill/SKILL.md').writeAsString('''
---
name: test-skill
description: A test skill
---
Body''');

        await File('${tempDir.path}/skills_lint.yaml').writeAsString('''
skills_lint:
  rules:
    path-does-not-exist:
      severity: error
      exclude: "[a-z"
''');

        final TestProcess process = await TestProcess.start('dart', [
          p.normalize(p.absolute('bin/skills_lint.dart')),
          '-s',
          'test-skill',
        ], workingDirectory: tempDir.path);

        final List<String> stderr = await process.stderr.rest.toList();
        expect(
          stderr.join('\n'),
          contains(
            'Configuration error: Global rules: Invalid value/type for parameter "exclude" in rule "path-does-not-exist"',
          ),
        );
        expect(stderr.join('\n'), contains('Expected RegExp (valid regular expression string)'));
        await process.shouldExit(1);
      },
    );
  });

  group('Configuration YAML Round-trip Serialization', () {
    test('round-trips empty configuration', () {
      const config = Configuration();
      final String yamlString = config.toYamlString();

      expect(yamlString, contains('skills_lint:'));
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips global rules with scalar severities', () {
      const config = Configuration(
        ruleConfigs: {
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          AbsolutePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
          TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(
        parsed.ruleConfigs[AbsolutePathsRule.ruleName]?.severity,
        equals(AnalysisSeverity.warning),
      );
      expect(
        parsed.ruleConfigs[TrailingWhitespaceRule.ruleName]?.severity,
        equals(AnalysisSeverity.disabled),
      );
      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips global rules with custom parameters', () {
      final config = Configuration(
        ruleConfigs: {
          PathDoesNotExistRule.ruleName: RuleConfigPatch(
            severity: AnalysisSeverity.error,
            parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
          ),
          PublishedSkillNameRule.ruleName: RuleConfigPatch(
            parameters: CustomRuleParameters(const {'package_name': 'my_package'}),
          ),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips directory target configurations', () {
      final config = Configuration(
        directoryConfigs: [
          const LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
            },
            ignoreFile: 'skills/.skillsignore',
          ),
          LintTargetConfig(
            path: '../../.agents/skills',
            ruleConfigs: {
              PathDoesNotExistRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
                parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
              ),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      final LintTargetConfig dir1 = parsed.directoryConfigs[0];
      expect(
        dir1.ruleConfigs[TrailingWhitespaceRule.ruleName]?.severity,
        equals(AnalysisSeverity.error),
      );

      final LintTargetConfig dir2 = parsed.directoryConfigs[1];
      expect(
        dir2.ruleConfigs[PathDoesNotExistRule.ruleName]?.parameters?['exclude'],
        equals('.*-workspace'),
      );
      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips individual skill target configurations', () {
      const config = Configuration(
        individualSkillConfigs: [
          LintTargetConfig(
            path: '.agents/skills/add-dart-lint-validation-rule',
            ruleConfigs: {
              PreventSkillsShPublishingRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
              ),
            },
            ignoreFile: 'custom_ignore.json',
          ),
          LintTargetConfig(
            path: '~/my-custom-skill',
            ruleConfigs: {
              RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.disabled),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      final LintTargetConfig skill1 = parsed.individualSkillConfigs[0];
      expect(
        skill1.ruleConfigs[PreventSkillsShPublishingRule.ruleName]?.severity,
        equals(AnalysisSeverity.error),
      );

      final LintTargetConfig skill2 = parsed.individualSkillConfigs[1];
      expect(
        skill2.ruleConfigs[RelativePathsRule.ruleName]?.severity,
        equals(AnalysisSeverity.disabled),
      );
      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });

    test('round-trips full composite configuration with all sections', () {
      final config = Configuration(
        ruleConfigs: const {
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          AbsolutePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
        directoryConfigs: [
          LintTargetConfig(
            path: '../../.agents/skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: const RuleConfigPatch(
                severity: AnalysisSeverity.error,
              ),
              PathDoesNotExistRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
                parameters: CustomRuleParameters(const {'exclude': '.*-workspace'}),
              ),
            },
            ignoreFile: '../../.agents/skills/ignore.json',
          ),
          const LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
              PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
        individualSkillConfigs: const [
          LintTargetConfig(
            path: '../../.agents/skills/add-dart-lint-validation-rule',
            ruleConfigs: {
              PreventSkillsShPublishingRule.ruleName: RuleConfigPatch(
                severity: AnalysisSeverity.error,
              ),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });
  });

  group('Configuration & LintTargetConfig Model Methods', () {
    test('Configuration methods produce valid maps and strings', () {
      const config = Configuration(
        ruleConfigs: {
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
        directoryConfigs: [
          LintTargetConfig(
            path: 'skills',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.warning),
            },
          ),
        ],
      );

      final Map<String, Object?> yamlMap = config.toYaml();
      expect(yamlMap.containsKey('skills_lint'), isTrue);

      final String yamlStr = config.toYamlString();
      expect(yamlStr, contains('skills_lint:'));
      expect(yamlStr, contains('check-relative-paths: error'));
      expect(yamlStr, contains('path: skills'));
    });

    test('LintTargetConfig methods serialize correctly', () {
      const target = LintTargetConfig(
        path: 'skills/my_skill',
        ruleConfigs: {
          PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
        ignoreFile: 'ignore.json',
      );

      final Map<String, Object?> map = target.toYaml();
      expect(map['path'], equals('skills/my_skill'));
      expect(map['ignore_file'], equals('ignore.json'));
      expect(map['rules'], equals({PublishedSkillNameRule.ruleName: 'error'}));

      final String yamlStr = target.toYamlString();
      expect(yamlStr, contains('path: skills/my_skill'));
      expect(yamlStr, contains('ignore_file: ignore.json'));
      expect(yamlStr, contains('published-skill-name: error'));
    });

    test('golden test: exact emitted YAML matches expected string', () {
      final config = Configuration(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfigPatch(severity: AnalysisSeverity.error),
          PathDoesNotExistRule.ruleName: RuleConfigPatch(
            severity: AnalysisSeverity.warning,
            parameters: CustomRuleParameters(const {'exclude': '.*-workspace', 'limit': 100}),
          ),
        },
        directoryConfigs: const [
          LintTargetConfig(
            path: 'skills',
            ignoreFile: 'custom_ignore.json',
            ruleConfigs: {
              TrailingWhitespaceRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
            },
          ),
        ],
      );

      final String yamlString = config.toYamlString();
      const expected = '''
skills_lint:
  rules:
    check-relative-paths: error
    path-does-not-exist:
      severity: warning
      exclude: ".*-workspace"
      limit: 100
  directories:
    - path: skills
      rules:
        check-trailing-whitespace: error
      ignore_file: custom_ignore.json
''';
      expect(yamlString, equals(expected));
    });

    test('round-trips rule configurations with rich parameter types', () {
      final config = Configuration(
        ruleConfigs: {
          'custom-rule': RuleConfigPatch(
            severity: AnalysisSeverity.error,
            parameters: CustomRuleParameters(const {
              'count': 42,
              'enabled': true,
              'tags': ['a', 'b', 'c'],
              'numbers': [1, 2, 3],
              'nested': {'k1': 'v1', 'k2': 10},
            }),
          ),
        },
      );

      final String yamlString = config.toYamlString();
      final Configuration parsed = ConfigParser.parse(yamlString);

      expect(parsed.toYamlString(), equals(config.toYamlString()));
    });
  });

  group('ConfigParser.parse Error Handling', () {
    test('records parsing errors on malformed YAML syntax', () {
      final Configuration config = ConfigParser.parse(': invalid: [');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Failed to parse content'));
    });

    test('records error on unrecognized top-level key', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  unknown_key: value
''');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Unrecognized top-level key "unknown_key"'));
    });

    test('records parsing error on unknown rule severity', () {
      final Configuration config = ConfigParser.parse('''
skills_lint:
  rules:
    check-relative-paths: eror
''');
      expect(config.parsingErrors, isNotEmpty);
      expect(
        config.parsingErrors.first,
        contains('Invalid severity "eror" for rule "check-relative-paths"'),
      );
    });

    test('records parsing error on non-map top-level YAML', () {
      final Configuration config = ConfigParser.parse('"scalar string"');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Top-level configuration must be a YAML map'));
    });

    test('records parsing error on non-map skills_lint block', () {
      final Configuration config = ConfigParser.parse('''
skills_lint: "not a map"
''');
      expect(config.parsingErrors, isNotEmpty);
      expect(config.parsingErrors.first, contains('Expected "skills_lint" to be a YAML map'));
    });

    test('returns empty configuration on content without skills_lint map', () {
      final Configuration config = ConfigParser.parse('other_tool: 123');
      expect(config.directoryConfigs, isEmpty);
      expect(config.individualSkillConfigs, isEmpty);
      expect(config.ruleConfigs, isEmpty);
      expect(config.parsingErrors, isEmpty);
    });
  });
}
