// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/output_format.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/rules/published_skill_name_rule.dart';
import 'package:skills_lint/src/validation_session.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

ValidationSession createTestSession({
  Configuration? config,
  Map<String, RuleConfigPatch> resolvedRuleConfigs = const {},
  String? ignoreFileOverride,
  List<SkillRule> customRules = const [],
  bool printWarnings = true,
  bool fastFail = false,
  bool quiet = true,
  bool generateBaseline = false,
  bool fix = false,
  bool fixApply = false,
  OutputFormat format = OutputFormat.text,
}) => ValidationSession(
  config: config ?? const Configuration(),
  resolvedRuleConfigs: resolvedRuleConfigs,
  ignoreFileOverride: ignoreFileOverride,
  customRules: customRules,
  printWarnings: printWarnings,
  fastFail: fastFail,
  quiet: quiet,
  generateBaseline: generateBaseline,
  fix: fix,
  fixApply: fixApply,
  format: format,
);

void main() {
  group('ValidationSession', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('validation_session_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('validates a valid skill directory successfully', () async {
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: 'valid-skill',
        skillContent:
            '${buildFrontmatter(name: 'valid-skill', description: 'A valid skill description.')}\n# Valid Skill\n',
      );

      final ValidationSession session = createTestSession();
      final bool shouldContinue = await session.processIndividualSkill(skillDir.path);

      expect(shouldContinue, isTrue);
      expect(session.anySkillsValidated, isTrue);
      expect(session.anyFailed, isFalse);
    });

    test('records failure on invalid skill and respects fastFail flag', () async {
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: 'invalid_skill',
        skillContent:
            '${buildFrontmatter(name: 'Invalid_Skill_Name', description: 'A skill description.')}\n# Skill\n',
      );

      final ValidationSession session = createTestSession(fastFail: true);
      final bool shouldContinue = await session.processIndividualSkill(skillDir.path);

      expect(shouldContinue, isFalse);
      expect(session.anySkillsValidated, isTrue);
      expect(session.anyFailed, isTrue);
    });

    test('applies fix to SKILL.md and aligns directory name on disk when fixApply is true', () async {
      final pkgDir = Directory(p.join(tempDir.path, 'test_pkg'))..createSync(recursive: true);
      File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsStringSync('name: test_pkg\n');

      final skillsDir = Directory(p.join(pkgDir.path, 'skills'))..createSync(recursive: true);
      final Directory skillDir = await createDummySkill(
        skillsDir,
        name: 'dart-test-pkg-setup',
        skillContent:
            '${buildFrontmatter(name: 'dart-test-pkg-setup', description: 'Setup skill.')}\n# Setup\n',
      );

      final ValidationSession session = createTestSession(
        fix: true,
        fixApply: true,
        resolvedRuleConfigs: {
          PublishedSkillNameRule.ruleName: const RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      );

      final bool shouldContinue = await session.processIndividualSkill(skillDir.path);

      expect(shouldContinue, isTrue);
      expect(session.anySkillsValidated, isTrue);
      expect(session.anyFailed, isFalse);

      // Old directory should no longer exist; renamed directory should exist with updated SKILL.md.
      expect(skillDir.existsSync(), isFalse);
      final newDir = Directory(p.join(pkgDir.path, 'skills', 'test-pkg-setup'));
      expect(newDir.existsSync(), isTrue);
      final String content = File(p.join(newDir.path, 'SKILL.md')).readAsStringSync();
      expect(content, contains('name: test-pkg-setup'));
    });

    test('dry-run fix does not mutate SKILL.md or rename directory on disk', () async {
      final pkgDir = Directory(p.join(tempDir.path, 'test_pkg'))..createSync(recursive: true);
      File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsStringSync('name: test_pkg\n');

      final skillsDir = Directory(p.join(pkgDir.path, 'skills'))..createSync(recursive: true);
      final Directory skillDir = await createDummySkill(
        skillsDir,
        name: 'dart-test-pkg-setup',
        skillContent:
            '${buildFrontmatter(name: 'dart-test-pkg-setup', description: 'Setup skill.')}\n# Setup\n',
      );

      final ValidationSession session = createTestSession(
        fix: true,
        resolvedRuleConfigs: {
          PublishedSkillNameRule.ruleName: const RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      );

      final bool shouldContinue = await session.processIndividualSkill(skillDir.path);

      expect(shouldContinue, isTrue);
      expect(session.anySkillsValidated, isTrue);
      expect(session.anyFailed, isTrue);

      // Verify original directory and file contents remain intact.
      expect(skillDir.existsSync(), isTrue);
      final String content = File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync();
      expect(content, contains('name: dart-test-pkg-setup'));
    });
    test('formatOutput produces non-empty output for text, json, and sarif formats', () async {
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: 'sample-skill',
        skillContent: '${buildFrontmatter(name: "sample-skill")}\n# Sample\n',
      );

      final ValidationSession textSession = createTestSession(quiet: false);
      await textSession.processIndividualSkill(skillDir.path);
      final String textOutput = textSession.formatOutput();
      expect(textOutput, contains('Validating skill: sample-skill'));
      expect(textOutput, contains('Skill is valid.'));

      final ValidationSession jsonSession = createTestSession(format: OutputFormat.json);
      await jsonSession.processIndividualSkill(skillDir.path);
      final String jsonOutput = jsonSession.formatOutput();
      expect(jsonOutput, contains('"isValid": true'));

      final ValidationSession sarifSession = createTestSession(format: OutputFormat.sarif);
      await sarifSession.processIndividualSkill(skillDir.path);
      final String sarifOutput = sarifSession.formatOutput();
      expect(sarifOutput, contains('"version": "2.1.0"'));
    });

    test('records a failure and continues when the skills root cannot be listed', () async {
      final rootDir = Directory(p.join(tempDir.path, 'unlistable'))..createSync();
      await createDummySkill(
        rootDir,
        name: 'some-skill',
        skillContent: '${buildFrontmatter(name: 'some-skill')}\n# Skill\n',
      );
      _chmod('000', rootDir.path);
      addTearDown(() => _chmod('755', rootDir.path));

      final ValidationSession session = createTestSession();
      final bool shouldContinue = await session.processSkillRoot(rootDir.path);

      expect(shouldContinue, isTrue);
      expect(session.anyFailed, isTrue);
      expect(
        session.results.expand((r) => r.validationErrors).map((e) => e.message),
        contains(contains('Failed to list children of')),
      );
      // Skipped on Windows: the test removes permissions with the POSIX `chmod`
      // command (see `_chmod`), which Windows does not provide, and NTFS access
      // is controlled by ACLs rather than mode bits.
    }, testOn: '!windows');

    test('continues when the custom ignore file and baseline cannot be written', () async {
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: 'baseline-skill',
        skillContent: '${buildFrontmatter(name: 'Bad_Name')}\n# Skill\n',
      );
      // The parent directory does not exist, so both the empty ignore file
      // created on load and the baseline written afterwards fail with a
      // FileSystemException.
      final String ignorePath = p.join(tempDir.path, 'missing-dir', 'ignores.json');

      final ValidationSession session = createTestSession(
        ignoreFileOverride: ignorePath,
        generateBaseline: true,
      );
      final bool shouldContinue = await session.processIndividualSkill(skillDir.path);

      expect(shouldContinue, isTrue);
      expect(session.anySkillsValidated, isTrue);
      expect(File(ignorePath).existsSync(), isFalse);
    });

    test('leaves the skill directory in place when the rename fails', () async {
      final pkgDir = Directory(p.join(tempDir.path, 'test_pkg'))..createSync(recursive: true);
      File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsStringSync('name: test_pkg\n');
      final skillsDir = Directory(p.join(pkgDir.path, 'skills'))..createSync(recursive: true);
      final Directory skillDir = await createDummySkill(
        skillsDir,
        name: 'dart-test-pkg-setup',
        skillContent:
            '${buildFrontmatter(name: 'dart-test-pkg-setup', description: 'Setup skill.')}\n# Setup\n',
      );
      // A read-only parent lets the fixer rewrite SKILL.md but makes the
      // directory rename fail with a FileSystemException.
      _chmod('555', skillsDir.path);
      addTearDown(() => _chmod('755', skillsDir.path));

      final ValidationSession session = createTestSession(
        fix: true,
        fixApply: true,
        resolvedRuleConfigs: {
          PublishedSkillNameRule.ruleName: const RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      );
      final bool shouldContinue = await session.processIndividualSkill(skillDir.path);

      expect(shouldContinue, isTrue);
      expect(skillDir.existsSync(), isTrue);
      expect(Directory(p.join(skillsDir.path, 'test-pkg-setup')).existsSync(), isFalse);
      // Skipped on Windows: the test removes permissions with the POSIX `chmod`
      // command (see `_chmod`), which Windows does not provide, and NTFS access
      // is controlled by ACLs rather than mode bits.
    }, testOn: '!windows');
  });
}

/// Sets POSIX permission [mode] on [path].
void _chmod(String mode, String path) {
  final ProcessResult result = Process.runSync('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw StateError('chmod $mode $path failed: ${result.stderr}');
  }
}
