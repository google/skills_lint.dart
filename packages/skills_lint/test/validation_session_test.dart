// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
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
}) => ValidationSession(
  config: config ?? Configuration(),
  resolvedRuleConfigs: resolvedRuleConfigs,
  ignoreFileOverride: ignoreFileOverride,
  customRules: customRules,
  printWarnings: printWarnings,
  fastFail: fastFail,
  quiet: quiet,
  generateBaseline: generateBaseline,
  fix: fix,
  fixApply: fixApply,
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
  });
}
