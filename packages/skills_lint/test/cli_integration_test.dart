// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/entry_point.dart';
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/models/ignore_entry.dart';
import 'package:skills_lint/src/models/skills_ignores.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

void main() {
  group('CLI Integration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cli_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('de-duplicates baseline entries for multiple identical rule failures', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Link 1](missing1.md)\n[Link 2](missing2.md)\n',
      );
      // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/18
      final configFile = File('${tempDir.path}/skills_lint.yaml');
      await configFile.writeAsString('''
skills_lint:
  rules:
    check-relative-paths: error
''');

      // Run with --generate-baseline
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--generate-baseline',
      ], workingDirectory: tempDir.path);
      await process.shouldExit(0);

      final ignoreFile = File('${skillDir.path}/$defaultIgnoreFileName');
      expect(ignoreFile.existsSync(), isTrue);

      final String content = await ignoreFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final skills = json[SkillsIgnores.skillsKey] as Map<String, dynamic>;
      final ignores = skills['test-skill'] as List;

      // Should be 1 entry only! Both relative link failures utilize the same ruleId/fileName de-duplication.
      expect(ignores.length, equals(1));
    });

    test('individual skill baseline is loaded on subsequent runs', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](missing.md)\n');
      // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/18
      final configFile = File('${tempDir.path}/skills_lint.yaml');
      await configFile.writeAsString('''
skills_lint:
  rules:
    check-relative-paths: error
''');

      final TestProcess genProcess = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--generate-baseline',
      ], workingDirectory: tempDir.path);
      await genProcess.shouldExit(0);

      final ignoreFile = File('${skillDir.path}/$defaultIgnoreFileName');
      expect(ignoreFile.existsSync(), isTrue);

      final TestProcess runProcess = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);
      await runProcess.shouldExit(0);
    });

    test('baseline entries name files relative to the skill directory', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](missing.md)\n');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
        '--generate-baseline',
        '--check-relative-paths',
      ], workingDirectory: tempDir.path);
      await process.shouldExit(0);

      final json =
          jsonDecode(await File('${skillDir.path}/$defaultIgnoreFileName').readAsString())
              as Map<String, dynamic>;
      final skills = json[SkillsIgnores.skillsKey] as Map<String, dynamic>;
      final List<Map<String, dynamic>> entries = (skills['test-skill'] as List)
          .cast<Map<String, dynamic>>();

      // An absolute name would only match on the machine that generated it.
      expect(entries.single[IgnoreEntry.fileNameKey], equals('SKILL.md'));
    });

    test('a baseline names the skill directory itself relative to the skill', () async {
      // path-does-not-exist reports the skill directory rather than a file
      // inside it, so the recorded name has no file to be relative to.
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();

      final TestProcess generate = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
        '--generate-baseline',
      ], workingDirectory: tempDir.path);
      await generate.shouldExit(0);

      final json =
          jsonDecode(await File('${skillDir.path}/$defaultIgnoreFileName').readAsString())
              as Map<String, dynamic>;
      final skills = json[SkillsIgnores.skillsKey] as Map<String, dynamic>;
      final List<Map<String, dynamic>> entries = (skills['test-skill'] as List)
          .cast<Map<String, dynamic>>();

      expect(
        entries.map((Map<String, dynamic> entry) => entry[IgnoreEntry.fileNameKey]),
        everyElement(equals('.')),
        reason: 'An absolute name would only match on the machine that generated it.',
      );

      // The recorded name has to keep suppressing the error it was written for.
      final TestProcess validate = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
      ], workingDirectory: Directory.systemTemp.path);
      await validate.shouldExit(0);
    });

    test('a baseline suppresses errors when validated from another directory', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](missing.md)\n');

      final TestProcess generate = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--generate-baseline',
        '--check-relative-paths',
      ], workingDirectory: tempDir.path);
      await generate.shouldExit(0);

      final TestProcess validate = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
        '--check-relative-paths',
      ], workingDirectory: Directory.systemTemp.path);
      await validate.shouldExit(0);
    });

    test('a baseline written by an earlier version keeps suppressing errors', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](missing.md)\n');
      // Names as spelled on the command line, the form written before baselines
      // stored names relative to the skill directory.
      await File('${skillDir.path}/$defaultIgnoreFileName').writeAsString(
        jsonEncode({
          SkillsIgnores.skillsKey: {
            'test-skill': [
              {
                IgnoreEntry.ruleIdKey: 'check-relative-paths',
                IgnoreEntry.fileNameKey: 'test-skill/SKILL.md',
              },
            ],
          },
        }),
      );

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
        '--check-relative-paths',
      ], workingDirectory: tempDir.path);
      await process.shouldExit(0);
    });

    test(
      'cross-skill baseline de-duplicates and suppresses all errors across different skills',
      () async {
        final Directory skillsDir = await Directory('${tempDir.path}/skills').create();

        // Create skill-one with a broken link
        final Directory skill1Dir = await Directory('${skillsDir.path}/skill-one').create();
        await File('${skill1Dir.path}/SKILL.md').writeAsString(
          '${buildFrontmatter(name: 'skill-one', description: 'Skill one with a broken link')}[Link to nowhere](../nowhere/SKILL.md)\n',
        );

        // Create skill-two with a broken link
        final Directory skill2Dir = await Directory('${skillsDir.path}/skill-two').create();
        await File('${skill2Dir.path}/SKILL.md').writeAsString(
          '${buildFrontmatter(name: 'skill-two', description: 'Skill two with a broken link')}[Link to nowhere](../nowhere/SKILL.md)\n',
        );

        final configFile = File('${tempDir.path}/skills_lint.yaml');
        await configFile.writeAsString('''
skills_lint:
  directories:
    - path: "skills"
      rules:
        check-relative-paths: error
      ignore_file: "$defaultIgnoreFileName"
''');

        // 1. Run with --generate-baseline. It should evaluate all skills and write both to the baseline!
        final TestProcess genProcess = await TestProcess.start('dart', [
          p.normalize(p.absolute('bin/skills_lint.dart')),
          '-d',
          'skills',
          '--generate-baseline',
        ], workingDirectory: tempDir.path);
        await genProcess.shouldExit(0); // Exits 0 if --generate-baseline is passed

        final ignoreFile = File('${tempDir.path}/$defaultIgnoreFileName');
        expect(ignoreFile.existsSync(), isTrue);

        final String content = await ignoreFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final skills = json[SkillsIgnores.skillsKey] as Map<String, dynamic>;

        expect(skills.containsKey('skill-one'), isTrue);
        expect(skills.containsKey('skill-two'), isTrue);

        // 2. Run again silently. It should succeed with exit 0 because all errors are ignored!
        final TestProcess runProcess = await TestProcess.start('dart', [
          p.normalize(p.absolute('bin/skills_lint.dart')),
          '-d',
          'skills',
          '-q',
        ], workingDirectory: tempDir.path);
        await runProcess.shouldExit(0);
      },
    );

    test('exits with 0 and success message for valid skill', () async {
      final Directory skillDir = await Directory('${tempDir.path}/valid-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'valid-skill', description: 'A valid skill')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
      ]);

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains(skillIsValidMsg));
      await process.shouldExit(0);
    });

    test('exits with 1 and error message for invalid skill', () async {
      final Directory skillDir = await Directory('${tempDir.path}/invalid-skill').create();
      // SKILL.md is missing

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
      ]);

      final List<String> stderr = await process.stderr.rest.toList();
      final String stderrStr = stderr.join('\n');
      expect(stderrStr, contains(skillIsInvalidMsg));
      expect(stderrStr, contains('SKILL.md is missing'));
      await process.shouldExit(1);
    });

    test('exits with 0 and validates subdirectories if named "skills"', () async {
      final Directory skillsDir = await Directory('${tempDir.path}/skills').create();
      final Directory skill1 = await Directory('${skillsDir.path}/skill-a').create();
      await File(
        '${skill1.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'skill-a', description: 'Skill A')}Body');

      final Directory skill2 = await Directory('${skillsDir.path}/skill-b').create();
      await File(
        '${skill2.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'skill-b', description: 'Skill B')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-d',
        skillsDir.path,
      ]);

      // Verify outputs for both skills (sorted order)
      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');
      expect(stdoutStr, contains(evaluatingDirMsg));
      expect(stdoutStr, contains('--- Validating skill: skill-a ---'));
      expect(stdoutStr, contains(skillIsValidMsg));

      expect(stdoutStr, contains('--- Validating skill: skill-b ---'));
      expect(stdoutStr, contains(skillIsValidMsg));

      await process.shouldExit(0);
    });

    test('ignores subdirectories starting with a dot "." in "skills" folder', () async {
      final Directory skillsDir = await Directory('${tempDir.path}/skills').create();
      final Directory skill1 = await Directory('${skillsDir.path}/skill-a').create();
      await File(
        '${skill1.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'skill-a', description: 'Skill A')}Body');

      await Directory('${skillsDir.path}/.dart_tool').create();

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-d',
        skillsDir.path,
      ]);

      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');
      expect(stdoutStr, contains('--- Validating skill: skill-a ---'));
      expect(stdoutStr, contains(skillIsValidMsg));
      expect(stdoutStr, isNot(contains('.dart_tool')));

      await process.shouldExit(0);
    });

    test('exits with 1 if any subdirectory skill fails in "skills" folder', () async {
      final Directory skillsDir = await Directory('${tempDir.path}/skills').create();
      final Directory skill1 = await Directory('${skillsDir.path}/skill-a').create();
      await File(
        '${skill1.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'skill-a', description: 'Skill A')}Body');

      await Directory('${skillsDir.path}/skill-b').create(); // No SKILL.md

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-d',
        skillsDir.path,
      ]);

      // Verify outputs
      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('--- Validating skill: skill-a ---'));
      expect(stdout.join('\n'), contains(skillIsValidMsg));

      expect(stdout.join('\n'), contains('--- Validating skill: skill-b ---'));
      final List<String> stderr = await process.stderr.rest.toList();
      expect(stderr.join('\n'), contains(skillIsInvalidMsg));
      await process.shouldExit(1);
    });

    test(
      'exits with 1 early and does not process subsequent skills if --fast-fail is passed',
      () async {
        final Directory skillsDir = await Directory('${tempDir.path}/skills').create();

        await Directory('${skillsDir.path}/skill-a').create();
        // skill-a does not create SKILL.md, so it is invalid and will fail first (sorted order)

        await Directory('${skillsDir.path}/skill-b').create();
        await File(
          '${p.join(tempDir.path, 'skills', 'skill-b')}/SKILL.md',
        ).writeAsString('${buildFrontmatter(name: 'skill-b', description: 'Skill B')}Body');

        final TestProcess process = await TestProcess.start('dart', [
          'bin/skills_lint.dart',
          '-d',
          skillsDir.path,
          '--fast-fail',
        ]);

        // Verify outputs for skill-a
        final List<String> stdout = await process.stdout.rest.toList();
        final String stdoutStr = stdout.join('\n');
        expect(stdoutStr, contains(evaluatingDirMsg));
        expect(stdoutStr, contains('--- Validating skill: skill-a ---'));

        final List<String> stderr = await process.stderr.rest.toList();
        expect(stderr.join('\n'), contains(skillIsInvalidMsg));

        // Since process exits after skill-a, stdout should be closed and no further lines (like skill-b) should appear.
        await process.shouldExit(1);
      },
    );

    test('exits with 0 and suppresses success messages if --quiet is passed', () async {
      final Directory skillDir = await Directory('${tempDir.path}/valid-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'valid-skill', description: 'A valid skill')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--quiet',
      ]);

      await process.shouldExit(0);

      // Stdout should be empty for a valid skill in quiet mode
      final List<String> rest = await process.stdout.rest.toList();
      expect(rest, isEmpty);
    });
    test('prints a first-run guide to stdout and exits 64 when no defaults exist', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');
      expect(stdoutStr, contains('skills_lint: a linter for Agent Skills'));
      expect(stdoutStr, contains('--skill ./path/to/my-skill'));
      expect(stdoutStr, contains('--skills-directory ./path/to/skills-root'));
      expect(stdoutStr, contains('.claude/skills/<my-skill>/SKILL.md'));
      expect(stdoutStr, contains('.agents/skills/<my-skill>/SKILL.md'));
      expect(stdoutStr, contains('agentskills.io/specification'));
      expect(stdoutStr, contains('--help'));
      await process.shouldExit(64);
    });

    test('picks up .claude/skills when no flags passed and it exists', () async {
      final Directory claudeDir = await Directory(
        '${tempDir.path}/.claude/skills',
      ).create(recursive: true);
      final Directory skillDir = await Directory('${claudeDir.path}/valid-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'valid-skill', description: 'A valid skill')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
      ], workingDirectory: tempDir.path);

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('Skill is valid.'));
      await process.shouldExit(0);
    });
    test('expands ~/ to HOME environment variable', () async {
      final Directory skillDir = await Directory('${tempDir.path}/some-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'some-skill')}Body');

      final TestProcess process = await TestProcess.start(
        'dart',
        [p.normalize(p.absolute('bin/skills_lint.dart')), '-s', '~/some-skill'],
        environment: {'HOME': tempDir.path},
      );

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('Skill is valid.'));
      await process.shouldExit(0);
    });

    test('overrides valid-yaml-metadata flag to disabled', () async {
      final Directory skillDir = await Directory('${tempDir.path}/invalid-yaml').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('Invalid YAML No Frontmatter');

      // 1. Run normally. Should fail because valid-yaml-metadata defaults to true (error).
      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
      ]);
      await process.shouldExit(1);

      // 2. Run with --no-valid-yaml-metadata. Should pass because the check is disabled!
      final TestProcess noYamlProcess = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--no-valid-yaml-metadata',
      ]);
      await noYamlProcess.shouldExit(0);
    });

    test('fails if -d specifies a directory with zero skills', () async {
      final Directory emptyDir = await Directory('${tempDir.path}/empty-root').create();

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-d',
        emptyDir.path,
      ]);

      await process.shouldExit(1);
      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains('No skills found to validate in the specified directories.'),
      );
    });

    test('fails if -d specifies a single skill directory (no sub-folders found)', () async {
      final Directory skillAsRoot = await Directory('${tempDir.path}/single-skill-root').create();
      await File('${skillAsRoot.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'single-skill-root', description: 'Not a root, but a skill folder.')}Body',
      );

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-d',
        skillAsRoot.path,
      ]);

      await process.shouldExit(1);
      final List<String> stderr = await process.stderr.rest.toList();
      expect(
        stderr.join('\n'),
        contains(
          'appears to be an individual skill. Use --skill / -s instead of -d / --skills-directory.',
        ),
      );
    });

    test('validates multiple skills with multiple -s flags', () async {
      final Directory skill1 = await Directory('${tempDir.path}/skill-1').create();
      await File(
        '${skill1.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'skill-1', description: 'Skill 1')}Body');

      final Directory skill2 = await Directory('${tempDir.path}/skill-2').create();
      await File(
        '${skill2.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'skill-2', description: 'Skill 2')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skill1.path,
        '-s',
        skill2.path,
      ]);

      await process.shouldExit(0);
      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');
      expect(stdoutStr, contains('--- Validating skill: skill-1 ---'));
      expect(stdoutStr, contains('--- Validating skill: skill-2 ---'));
    });

    test('handles malformed JSON ignore-file gracefully by falling back', () async {
      final malformedFile = File('${tempDir.path}/malformed.json');
      await malformedFile.writeAsString('{ malformed json }');

      final Directory skillFolder = await Directory('${tempDir.path}/skill-x').create();
      await File(
        '${skillFolder.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'skill-x', description: 'Valid skill')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillFolder.path,
        '--ignore-file',
        malformedFile.path,
      ]);

      await process.shouldExit(0); // Valid skill should still pass
      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('Evaluating directory:'));
    });

    test('CLI help displays all registered rules', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '--help',
      ]);
      await process.shouldExit(0);
      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');

      for (final CheckType check in RuleRegistry.allChecks) {
        expect(stdoutStr, contains(check.name));
      }
    });

    test('CLI help displays path-does-not-exist', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '--help',
      ]);
      await process.shouldExit(0);
      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');

      expect(stdoutStr, contains(Validator.pathDoesNotExist));
    });

    test('ignores directory missing SKILL.md if listed in ignore file', () async {
      final Directory skillsDir = await Directory('${tempDir.path}/skills').create();

      // Create a valid skill
      final Directory skillDir = await Directory('${skillsDir.path}/valid-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('---\nname: valid-skill\ndescription: A valid skill\n---\nBody');

      // Create a non-skill directory
      await Directory('${skillsDir.path}/contributing').create();

      // Create ignore file
      final ignoreFile = File('${tempDir.path}/$defaultIgnoreFileName');
      await ignoreFile.writeAsString(
        jsonEncode({
          SkillsIgnores.skillsKey: {
            'contributing': [
              {
                IgnoreEntry.ruleIdKey: Validator.pathDoesNotExist,
                IgnoreEntry.fileNameKey: 'skills/contributing',
              },
            ],
          },
        }),
      );

      final configFile = File('${tempDir.path}/skills_lint.yaml');
      await configFile.writeAsString('''
skills_lint:
  directories:
    - path: "skills"
      ignore_file: "$defaultIgnoreFileName"
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-d',
        'skills',
      ], workingDirectory: tempDir.path);

      await process.shouldExit(0);

      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');
      expect(stdoutStr, contains('--- Validating skill: valid-skill ---'));
      expect(stdoutStr, contains('--- Validating skill: contributing ---'));
    });

    test('CLI reports trailing whitespace as error when enabled via config', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}Line with 1 space \n');

      final configFile = File('${tempDir.path}/skills_lint.yaml');
      await configFile.writeAsString('''
skills_lint:
  directories:
    - path: "test-skill"
      rules:
        check-trailing-whitespace: error
''');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'test-skill',
      ], workingDirectory: tempDir.path);

      final List<String> stderr = await process.stderr.rest.toList();
      final String stderrStr = stderr.join('\n');
      expect(stderrStr, contains('has 1 trailing space(s)'));
      await process.shouldExit(1);
    });

    test('--fix --dry-run shows diff but does not modify file', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}Line with 1 space \n');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--fix',
        '--dry-run',
        '--check-trailing-whitespace',
      ]);

      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');
      expect(stdoutStr, contains('[Dry Run] Proposed changes for test-skill (SKILL.md):'));

      await process.shouldExit(1);

      // Verify file was not modified
      final String content = await File('${skillDir.path}/SKILL.md').readAsString();
      expect(content, contains('Line with 1 space \n'));
    });

    test('--fix without --dry-run writes fixes to disk', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}Line with 1 space \n');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--fix',
        '--check-trailing-whitespace',
      ]);

      final List<String> stdout = await process.stdout.rest.toList();
      expect(stdout.join('\n'), contains('Applied fixes for test-skill'));

      await process.shouldExit(0);

      // Verify file was modified
      final String content = await File('${skillDir.path}/SKILL.md').readAsString();
      expect(content, isNot(contains('Line with 1 space \n')));
      expect(content, contains('Line with 1 space\n'));
    });

    test('--fix-apply alias still works but prints a deprecation notice', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}Line with 1 space \n');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--fix-apply',
        '--check-trailing-whitespace',
      ]);

      final List<String> stdout = await process.stdout.rest.toList();
      final List<String> stderr = await process.stderr.rest.toList();
      expect(stderr.join('\n'), contains(fixApplyDeprecationMsg));
      expect(stdout.join('\n'), contains('Applied fixes for test-skill'));

      await process.shouldExit(0);

      // File still modified — alias preserves behavior.
      final String content = await File('${skillDir.path}/SKILL.md').readAsString();
      expect(content, contains('Line with 1 space\n'));
    });

    test('--fix does not modify file if lint is ignored', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}Line with 1 space \n');

      final ignoreFile = File('${skillDir.path}/$defaultIgnoreFileName');
      await ignoreFile.writeAsString(
        jsonEncode({
          SkillsIgnores.skillsKey: {
            'test-skill': [
              {
                IgnoreEntry.ruleIdKey: 'check-trailing-whitespace',
                IgnoreEntry.fileNameKey: 'SKILL.md',
              },
            ],
          },
        }),
      );

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--fix',
        '--check-trailing-whitespace',
      ]);

      await process.shouldExit(0);

      final String content = await File('${skillDir.path}/SKILL.md').readAsString();
      expect(content, contains('Line with 1 space \n'));
    });

    test('--fix does not modify file if invalid-skill-name is ignored', () async {
      final Directory skillDir = await Directory('${tempDir.path}/my_skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: wrong-name
description: A test skill
---
Body''');

      final ignoreFile = File('${skillDir.path}/$defaultIgnoreFileName');
      await ignoreFile.writeAsString(
        jsonEncode({
          SkillsIgnores.skillsKey: {
            'my_skill': [
              {IgnoreEntry.ruleIdKey: 'invalid-skill-name', IgnoreEntry.fileNameKey: 'SKILL.md'},
            ],
          },
        }),
      );

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--fix',
      ]);

      await process.shouldExit(0);

      final String content = await File('${skillDir.path}/SKILL.md').readAsString();
      expect(content, contains('name: wrong-name'));
    });

    test('validates published-skill-name when enabled via CLI flag', () async {
      final pkgDir = Directory('${tempDir.path}/test_pkg');
      await pkgDir.create(recursive: true);
      await File('${pkgDir.path}/pubspec.yaml').writeAsString('name: test_pkg\n');
      final skillDir = Directory('${pkgDir.path}/skills/dart-test-pkg-setup');
      await skillDir.create(recursive: true);
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: dart-test-pkg-setup
description: Setup skill
---
Body''');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--published-skill-name',
      ]);

      await process.shouldExit(1);
      final List<String> stderr = await process.stderr.rest.toList();
      final String stderrStr = stderr.join('\n');
      expect(
        stderrStr,
        contains(
          'Skill "dart-test-pkg-setup" does not follow the Dart package published skill naming convention',
        ),
      );
      expect(stderrStr, contains('Suggested name: "test-pkg-setup"'));
      expect(stderrStr, contains('Fix by re-running your validation command with `--fix`'));
    });

    test('--fix on published-skill-name aligns frontmatter and renames directory', () async {
      final pkgDir = Directory('${tempDir.path}/test_pkg_fix');
      await pkgDir.create(recursive: true);
      await File('${pkgDir.path}/pubspec.yaml').writeAsString('name: test_pkg\n');
      final skillDir = Directory('${pkgDir.path}/skills/dart-test-pkg-setup');
      await skillDir.create(recursive: true);
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: dart-test-pkg-setup
description: Setup skill
---
Body''');

      final TestProcess process = await TestProcess.start('dart', [
        'bin/skills_lint.dart',
        '-s',
        skillDir.path,
        '--published-skill-name',
        '--fix',
      ]);

      await process.shouldExit(0);
      final List<String> stdout = await process.stdout.rest.toList();
      final String stdoutStr = stdout.join('\n');
      expect(stdoutStr, contains('Renamed skill directory: dart-test-pkg-setup -> test-pkg-setup'));

      // Check that old directory is gone and new directory exists with updated SKILL.md
      expect(skillDir.existsSync(), isFalse);
      final newDir = Directory('${pkgDir.path}/skills/test-pkg-setup');
      expect(newDir.existsSync(), isTrue);
      final String content = await File('${newDir.path}/SKILL.md').readAsString();
      expect(content, contains('name: test-pkg-setup'));
    });

    test(
      '--fix --dry-run on published-skill-name previews proposed directory rename without renaming',
      () async {
        final pkgDir = Directory('${tempDir.path}/test_pkg_dry');
        await pkgDir.create(recursive: true);
        await File('${pkgDir.path}/pubspec.yaml').writeAsString('name: test_pkg\n');
        final skillDir = Directory('${pkgDir.path}/skills/dart-test-pkg-setup');
        await skillDir.create(recursive: true);
        await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: dart-test-pkg-setup
description: Setup skill
---
Body''');

        final TestProcess process = await TestProcess.start('dart', [
          'bin/skills_lint.dart',
          '-s',
          skillDir.path,
          '--published-skill-name',
          '--fix',
          '--dry-run',
        ]);

        await process.shouldExit(1);
        final List<String> stdout = await process.stdout.rest.toList();
        final String stdoutStr = stdout.join('\n');
        expect(
          stdoutStr,
          contains('[Dry Run] Proposed directory rename: dart-test-pkg-setup -> test-pkg-setup'),
        );

        // Verify directory was NOT renamed on disk
        expect(skillDir.existsSync(), isTrue);
        final String content = await File('${skillDir.path}/SKILL.md').readAsString();
        expect(content, contains('name: dart-test-pkg-setup'));
      },
    );

    test(
      '--fix with trailing whitespace fix does not rename directory when invalid-skill-name is ignored',
      () async {
        final skillDir = Directory('${tempDir.path}/skill-dir-name');
        await skillDir.create(recursive: true);
        await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: ignored-frontmatter-name
description: A description
---
Body with trailing space   
''');
        final ignoreFile = File('${tempDir.path}/$defaultIgnoreFileName');
        await ignoreFile.writeAsString(
          jsonEncode({
            SkillsIgnores.skillsKey: {
              'skill-dir-name': [
                {IgnoreEntry.ruleIdKey: 'invalid-skill-name', IgnoreEntry.fileNameKey: 'SKILL.md'},
              ],
            },
          }),
        );

        final TestProcess process = await TestProcess.start('dart', [
          'bin/skills_lint.dart',
          '-s',
          skillDir.path,
          '--check-trailing-whitespace',
          '--ignore-file',
          ignoreFile.path,
          '--fix',
        ]);

        await process.shouldExit(0);

        // Directory name must remain unchanged on disk
        expect(skillDir.existsSync(), isTrue);
        final String content = await File('${skillDir.path}/SKILL.md').readAsString();
        expect(content, contains('name: ignored-frontmatter-name'));
        expect(content, contains('Body with trailing space\n'));
      },
    );

    test('--format=sarif exits 0 and emits valid SARIF JSON for valid skill', () async {
      final Directory skillDir = await Directory('${tempDir.path}/valid-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'valid-skill', description: 'A valid skill')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
        '--format=sarif',
      ]);

      await process.shouldExit(0);
      final List<String> stdout = await process.stdout.rest.toList();
      final String output = stdout.join('\n');
      final jsonMap = jsonDecode(output) as Map<String, dynamic>;

      expect(
        jsonMap[r'$schema'],
        equals(
          'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json',
        ),
      );
      expect(jsonMap['version'], equals('2.1.0'));
      final runs = jsonMap['runs'] as List<dynamic>;
      expect(runs.length, equals(1));
      final run = runs.first as Map<String, dynamic>;
      final tool = run['tool'] as Map<String, dynamic>;
      final driver = tool['driver'] as Map<String, dynamic>;
      expect(driver['name'], equals('skills_lint'));
      expect(run['results'], isEmpty);
      expect(output, isNot(contains('Evaluating directory:')));
      expect(output, isNot(contains('Validating skill:')));
      expect(output, isNot(contains('Skill is valid.')));
    });

    test('--format=sarif exits 1 and emits SARIF findings for invalid skill', () async {
      final Directory skillDir = await Directory('${tempDir.path}/invalid-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('No frontmatter here');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
        '--format=sarif',
      ]);

      await process.shouldExit(1);
      final List<String> stdout = await process.stdout.rest.toList();
      final String output = stdout.join('\n');
      final jsonMap = jsonDecode(output) as Map<String, dynamic>;

      expect(jsonMap['version'], equals('2.1.0'));
      final runs = jsonMap['runs'] as List<dynamic>;
      final run = runs.first as Map<String, dynamic>;
      final results = run['results'] as List<dynamic>;
      expect(results, isNotEmpty);
      final firstResult = results.first as Map<String, dynamic>;
      expect(firstResult['ruleId'], equals('valid-yaml-metadata'));
      expect(firstResult['level'], equals('error'));
      expect(firstResult['locations'], isNotEmpty);
      expect(output, isNot(contains('Evaluating directory:')));
      expect(output, isNot(contains('Validating skill:')));
      expect(output, isNot(contains('Skill is invalid:')));
    });

    test('--format=json exits 0 and emits JSON array for valid skill', () async {
      final Directory skillDir = await Directory('${tempDir.path}/valid-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'valid-skill', description: 'A valid skill')}Body');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
        '--format=json',
      ]);

      await process.shouldExit(0);
      final List<String> stdout = await process.stdout.rest.toList();
      final String output = stdout.join('\n');
      final jsonList = jsonDecode(output) as List<dynamic>;

      expect(jsonList.length, equals(1));
      final skillObj = jsonList.first as Map<String, dynamic>;
      expect(skillObj['skillName'], equals('valid-skill'));
      expect(skillObj['isValid'], isTrue);
      expect(skillObj['errors'], isEmpty);
      expect(output, isNot(contains('Evaluating directory:')));
      expect(output, isNot(contains('Validating skill:')));
      expect(output, isNot(contains('Skill is valid.')));
    });

    test('--format=json exits 1 and emits JSON array with errors for invalid skill', () async {
      final Directory skillDir = await Directory('${tempDir.path}/invalid-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString('No frontmatter here');

      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        skillDir.path,
        '--format=json',
      ]);

      await process.shouldExit(1);
      final List<String> stdout = await process.stdout.rest.toList();
      final String output = stdout.join('\n');
      final jsonList = jsonDecode(output) as List<dynamic>;

      expect(jsonList.length, equals(1));
      final skillObj = jsonList.first as Map<String, dynamic>;
      expect(skillObj['skillName'], equals('invalid-skill'));
      expect(skillObj['isValid'], isFalse);
      expect(skillObj['errors'], isNotEmpty);
    });

    test('--format with invalid option exits with code 64', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'foo',
        '--format=invalid_format',
      ]);

      await process.shouldExit(64);
    });

    test('--fix combined with --format=sarif exits with code 64 and explains conflict', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'foo',
        '--fix',
        '--format=sarif',
      ]);

      await process.shouldExit(64);
      final List<String> stderr = await process.stderr.rest.toList();
      final String output = stderr.join();
      expect(output, contains('Cannot combine --fix with --format=sarif'));
      expect(output, contains('applying fixes modifies files described by the report'));
    });

    test('--fix combined with --format=json exits with code 64 and explains conflict', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'foo',
        '--fix',
        '--format=json',
      ]);

      await process.shouldExit(64);
      final List<String> stderr = await process.stderr.rest.toList();
      final String output = stderr.join();
      expect(output, contains('Cannot combine --fix with --format=json'));
      expect(output, contains('applying fixes modifies files described by the report'));
    });

    test('--fix-apply combined with --format=sarif exits with code 64', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '-s',
        'foo',
        '--fix-apply',
        '--format=sarif',
      ]);

      await process.shouldExit(64);
      final List<String> stderr = await process.stderr.rest.toList();
      final String output = stderr.join();
      expect(output, contains('Cannot combine --fix with --format=sarif'));
    });
  });

  group('Output Format Logging Hygiene', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cli_format_test.');
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](missing.md)\n');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> runAndAssertValidJson(List<String> args, int expectedExitCode) async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        ...args,
      ], workingDirectory: tempDir.path);

      final String stdoutString = await process.stdoutStream().join('\n');
      final String stderrString = await process.stderrStream().join('\n');
      await process.shouldExit(expectedExitCode);

      try {
        jsonDecode(stdoutString);
      } catch (e) {
        fail(
          'Stdout was not valid JSON! Error: $e\nStdout contents: $stdoutString\nStderr contents: $stderrString',
        );
      }
    }

    test('--format=sarif with --ignore-config produces valid JSON', () async {
      await runAndAssertValidJson(['--ignore-config', '--format=sarif', '-d', tempDir.path], 0);
    });

    test('--format=json with --ignore-config produces valid JSON', () async {
      await runAndAssertValidJson(['--ignore-config', '--format=json', '-d', tempDir.path], 0);
    });

    test('--format=sarif with -s (single skill) produces valid JSON', () async {
      // Setup ignore config to trigger "Ignoring configuration file due to ignore-config flag"
      await runAndAssertValidJson([
        '--ignore-config',
        '--format=sarif',
        '-s',
        '${tempDir.path}/test-skill',
      ], 0);
    });

    test('configuration warning under --format=sarif produces valid JSON', () async {
      // Cause a configuration warning by providing an unknown rule
      final configFile = File('${tempDir.path}/skills_lint.yaml');
      await configFile.writeAsString('''
skills_lint:
  rules:
    unknown-rule: error
''');

      await runAndAssertValidJson(['--format=sarif', '-d', tempDir.path], 0);
    });

    test('--format=text still produces the expected human output and is NOT JSON', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '--format=text',
        '-d',
        tempDir.path,
      ], workingDirectory: tempDir.path);

      final String stdoutString = await process.stdoutStream().join('\n');
      await process.shouldExit(0);

      try {
        jsonDecode(stdoutString);
        fail('Expected stdout to NOT be JSON');
      } catch (e) {
        // Expected
      }
    });
  });

  group('CLI Usage Routing', () {
    test('invalid flag writes usage to stderr with empty stdout and exit 64', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '--this-flag-does-not-exist',
      ]);

      final String stdoutString = await process.stdoutStream().join('\n');
      final String stderrString = await process.stderrStream().join('\n');
      await process.shouldExit(64);

      expect(stdoutString, isEmpty);
      expect(stderrString, isNotEmpty);
      expect(stderrString, contains('Usage: skills_lint'));
    });

    test('--help writes usage to stdout with empty stderr and exit 0', () async {
      final TestProcess process = await TestProcess.start('dart', [
        p.normalize(p.absolute('bin/skills_lint.dart')),
        '--help',
      ]);

      final String stdoutString = await process.stdoutStream().join('\n');
      final String stderrString = await process.stderrStream().join('\n');
      await process.shouldExit(0);

      expect(stdoutString, isNotEmpty);
      expect(stdoutString, contains('Usage: skills_lint'));
      expect(stderrString, isEmpty);
    });
  });
}
