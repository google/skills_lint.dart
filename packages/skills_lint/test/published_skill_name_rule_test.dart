// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/published_skill_name_rule.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('PublishedSkillNameRule', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('published_skill_rule_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('passes when skill name matches hyphenated package prefix', () async {
      final rule = PublishedSkillNameRule(
        severity: AnalysisSeverity.error,
        packageName: 'skills_lint',
      );
      final SkillContext context = createTestSkillContext(
        directory: Directory(p.join(tempDir.path, 'skills-lint-setup')),
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, isEmpty);
    });

    test('passes when skill name matches raw package prefix', () async {
      final rule = PublishedSkillNameRule(
        severity: AnalysisSeverity.error,
        packageName: 'skills_lint',
      );
      final SkillContext context = createTestSkillContext(
        directory: Directory(p.join(tempDir.path, 'skills_lint-setup')),
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, isEmpty);
    });

    test('flags skill name with extraneous prefix and suggests valid name', () async {
      final rule = PublishedSkillNameRule(
        severity: AnalysisSeverity.error,
        packageName: 'skills_lint',
      );
      final SkillContext context = createTestSkillContext(
        directory: Directory(p.join(tempDir.path, 'dart-skills-lint-setup')),
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, hasLength(1));
      expect(
        errors.first.message,
        contains(
          'Skill "dart-skills-lint-setup" does not follow the Dart package published skill naming convention for package "skills_lint".',
        ),
      );
      expect(errors.first.message, contains('Suggested valid name: "skills-lint-setup"'));
    });

    test('flags skill name missing package prefix and suggests valid name', () async {
      final rule = PublishedSkillNameRule(
        severity: AnalysisSeverity.error,
        packageName: 'skills_lint',
      );
      final SkillContext context = createTestSkillContext(
        directory: Directory(p.join(tempDir.path, 'setup')),
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, hasLength(1));
      expect(errors.first.message, contains('Suggested valid name: "skills-lint-setup"'));
    });

    test('auto-discovers package name from ancestor pubspec.yaml', () async {
      final pkgDir = Directory(p.join(tempDir.path, 'my_pkg'))..createSync(recursive: true);
      File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsStringSync('name: my_awesome_pkg\n');
      final skillDir = Directory(p.join(pkgDir.path, 'skills', 'setup'))
        ..createSync(recursive: true);

      final rule = PublishedSkillNameRule(severity: AnalysisSeverity.error);
      final SkillContext context = createTestSkillContext(directory: skillDir);

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, hasLength(1));
      expect(errors.first.message, contains('package "my_awesome_pkg"'));
      expect(errors.first.message, contains('Suggested valid name: "my-awesome-pkg-setup"'));
    });

    test('flags error when pubspec.yaml cannot be found and no package_name parameter', () async {
      final orphanDir = Directory(p.join(tempDir.path, 'orphan_skill'))
        ..createSync(recursive: true);

      final rule = PublishedSkillNameRule(severity: AnalysisSeverity.error);
      final SkillContext context = createTestSkillContext(directory: orphanDir);

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, hasLength(1));
      expect(
        errors.first.message,
        contains(
          'Unable to resolve enclosing Dart package name: no pubspec.yaml found in ancestor directories',
        ),
      );
    });

    test('resolves package name from explicit pubspec_path parameter', () async {
      final customPubspec = File(p.join(tempDir.path, 'custom_pubspec.yaml'))
        ..writeAsStringSync('name: custom_pkg\n');
      final orphanDir = Directory(p.join(tempDir.path, 'orphan_skill'))
        ..createSync(recursive: true);

      final rule = PublishedSkillNameRule(
        severity: AnalysisSeverity.error,
        pubspecPath: customPubspec.path,
      );
      final SkillContext context = createTestSkillContext(directory: orphanDir, name: 'setup');

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, hasLength(1));
      expect(errors.first.message, contains('package "custom_pkg"'));
      expect(errors.first.message, contains('Suggested valid name: "custom-pkg-setup"'));
    });

    test('skips when parsedYaml is null or yamlParsingError is present', () async {
      final rule = PublishedSkillNameRule(severity: AnalysisSeverity.error, packageName: 'my_pkg');
      final SkillContext context = createTestSkillContext(
        directory: tempDir,
        rawContent: '---\ninvalid: yaml : error\n---\n',
        yamlParsingError: 'Syntax error',
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, isEmpty);
    });

    group('suggestValidName', () {
      test('replaces prefix when skill contains package name', () {
        expect(
          PublishedSkillNameRule.suggestValidName('dart-skills-lint-setup', 'skills_lint'),
          'skills-lint-setup',
        );
        expect(
          PublishedSkillNameRule.suggestValidName('dart-skills_lint-validation', 'skills_lint'),
          'skills-lint-validation',
        );
      });

      test('prepends prefix when skill does not contain package name', () {
        expect(
          PublishedSkillNameRule.suggestValidName('setup', 'skills_lint'),
          'skills-lint-setup',
        );
        expect(
          PublishedSkillNameRule.suggestValidName('code-generation', 'serverpod'),
          'serverpod-code-generation',
        );
      });
    });

    group('fix', () {
      test('rewrites frontmatter name to suggested valid name', () async {
        final rule = PublishedSkillNameRule(
          severity: AnalysisSeverity.error,
          packageName: 'skills_lint',
        );
        const originalContent = '''
---
name: dart-skills-lint-setup
description: Setup skill
---

# Setup
''';

        final String fixedContent = await rule.fix('SKILL.md', originalContent, tempDir);

        expect(fixedContent, contains('name: skills-lint-setup'));
        expect(fixedContent, contains('description: Setup skill'));
      });

      test('leaves content unchanged if already valid', () async {
        final rule = PublishedSkillNameRule(
          severity: AnalysisSeverity.error,
          packageName: 'skills_lint',
        );
        const originalContent = '''
---
name: skills-lint-setup
description: Setup skill
---

# Setup
''';

        final String fixedContent = await rule.fix('SKILL.md', originalContent, tempDir);

        expect(fixedContent, originalContent);
      });
    });
  });
}
