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
      expect(errors.first.message, contains('Published skills must start with "skills-lint-"'));
      expect(errors.first.message, contains('Suggested name: "skills-lint-setup"'));
      expect(errors.first.message, contains('Fix with:\n`dart run skills_lint --fix`'));
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
      expect(errors.first.message, contains('Suggested name: "skills-lint-setup"'));
      expect(errors.first.message, contains('Fix with:\n`dart run skills_lint --fix`'));
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
      expect(errors.first.message, contains('Suggested name: "my-awesome-pkg-setup"'));
    });

    test(
      'explicit package_name parameter takes precedence over autodiscovered pubspec.yaml',
      () async {
        final pkgDir = Directory(p.join(tempDir.path, 'discovered_pkg'))
          ..createSync(recursive: true);
        File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsStringSync('name: discovered_pkg\n');
        final skillDir = Directory(p.join(pkgDir.path, 'skills', 'my-override-setup'))
          ..createSync(recursive: true);

        final rule = PublishedSkillNameRule(
          severity: AnalysisSeverity.error,
          packageName: 'my_override',
        );
        final SkillContext matchingContext = createTestSkillContext(
          directory: skillDir,
          name: 'my-override-setup',
        );

        final List<ValidationError> matchingErrors = await rule.validate(matchingContext);
        expect(matchingErrors, isEmpty);

        final SkillContext autodiscoveredContext = createTestSkillContext(
          directory: skillDir,
          name: 'discovered-pkg-setup',
        );
        final List<ValidationError> failingErrors = await rule.validate(autodiscoveredContext);
        expect(failingErrors, hasLength(1));
        expect(failingErrors.first.message, contains('package "my_override"'));
        expect(
          failingErrors.first.message,
          contains('Suggested name: "my-override-discovered-pkg-setup"'),
        );
      },
    );

    test('flags error when pubspec.yaml cannot be found and no package_name parameter', () async {
      final orphanDir = Directory(p.join(tempDir.path, 'orphan_skill'))
        ..createSync(recursive: true);

      final rule = PublishedSkillNameRule(severity: AnalysisSeverity.error);
      final SkillContext context = createTestSkillContext(directory: orphanDir);

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, hasLength(1));
      expect(
        errors.first.message,
        contains('Unable to resolve enclosing Dart package name. Add a pubspec.yaml'),
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
      expect(errors.first.message, contains('Suggested name: "custom-pkg-setup"'));
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

    test('passes when skill name matches exact hyphenated package name', () async {
      final rule = PublishedSkillNameRule(
        severity: AnalysisSeverity.error,
        packageName: 'skills_lint',
      );
      final SkillContext context = createTestSkillContext(
        directory: Directory(p.join(tempDir.path, 'skills-lint')),
        name: 'skills-lint',
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, isEmpty);
    });

    test('passes when skill name matches exact raw package name', () async {
      final rule = PublishedSkillNameRule(
        severity: AnalysisSeverity.error,
        packageName: 'skills_lint',
      );
      final SkillContext context = createTestSkillContext(
        directory: Directory(p.join(tempDir.path, 'skills_lint')),
        name: 'skills_lint',
      );

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors, isEmpty);
    });

    test('caches resolved package name in memory', () async {
      PublishedSkillNameRule.clearPackageCache();
      final pkgDir = Directory(p.join(tempDir.path, 'cached_pkg'))..createSync(recursive: true);
      final pubspecFile = File(p.join(pkgDir.path, 'pubspec.yaml'))
        ..writeAsStringSync('name: cached_pkg\n');
      final skillDir = Directory(p.join(pkgDir.path, 'skills', 'setup'))
        ..createSync(recursive: true);

      final String? first = PublishedSkillNameRule.resolvePackageName(startDirectory: skillDir);
      expect(first, 'cached_pkg');

      // Delete pubspec from disk; cached lookup should still return cached_pkg
      pubspecFile.deleteSync();
      final String? second = PublishedSkillNameRule.resolvePackageName(startDirectory: skillDir);
      expect(second, 'cached_pkg');

      // After clearing cache, lookup fails
      PublishedSkillNameRule.clearPackageCache();
      final String? third = PublishedSkillNameRule.resolvePackageName(startDirectory: skillDir);
      expect(third, isNull);
    });

    group('suggestValidName', () {
      test('handles exact package name match', () {
        expect(
          PublishedSkillNameRule.suggestValidName(
            currentName: 'skills_lint',
            packageName: 'skills_lint',
          ),
          'skills-lint',
        );
        expect(
          PublishedSkillNameRule.suggestValidName(
            currentName: 'skills-lint',
            packageName: 'skills_lint',
          ),
          'skills-lint',
        );
      });

      test('replaces prefix when skill contains package name', () {
        expect(
          PublishedSkillNameRule.suggestValidName(
            currentName: 'dart-skills-lint-setup',
            packageName: 'skills_lint',
          ),
          'skills-lint-setup',
        );
        expect(
          PublishedSkillNameRule.suggestValidName(
            currentName: 'dart-skills_lint-validation',
            packageName: 'skills_lint',
          ),
          'skills-lint-validation',
        );
      });

      test('normalizes underscores in suffix', () {
        expect(
          PublishedSkillNameRule.suggestValidName(
            currentName: 'skills_lint_setup',
            packageName: 'skills_lint',
          ),
          'skills-lint-setup',
        );
        expect(
          PublishedSkillNameRule.suggestValidName(
            currentName: 'setup_tool',
            packageName: 'skills_lint',
          ),
          'skills-lint-setup-tool',
        );
      });

      test('avoids false-positive substring matches inside unrelated words', () {
        expect(
          PublishedSkillNameRule.suggestValidName(currentName: 'splinter', packageName: 'lint'),
          'lint-splinter',
        );
        expect(
          PublishedSkillNameRule.suggestValidName(currentName: 'author-tools', packageName: 'auth'),
          'auth-author-tools',
        );
      });

      test('clamps long suggested names to max 64 characters', () {
        final String longName = 'a' * 60;
        final String suggested = PublishedSkillNameRule.suggestValidName(
          currentName: longName,
          packageName: 'my_pkg',
        );
        expect(suggested.length, lessThanOrEqualTo(64));
        expect(suggested, startsWith('my-pkg-'));
      });

      test('prepends prefix when skill does not contain package name', () {
        expect(
          PublishedSkillNameRule.suggestValidName(currentName: 'setup', packageName: 'skills_lint'),
          'skills-lint-setup',
        );
        expect(
          PublishedSkillNameRule.suggestValidName(
            currentName: 'code-generation',
            packageName: 'serverpod',
          ),
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

      test('leaves exact package name unchanged if already valid', () async {
        final rule = PublishedSkillNameRule(
          severity: AnalysisSeverity.error,
          packageName: 'skills_lint',
        );
        const originalContent = '''
---
name: skills-lint
description: Main skill
---

# Main
''';

        final String fixedContent = await rule.fix('SKILL.md', originalContent, tempDir);

        expect(fixedContent, originalContent);
      });
    });
  });
}
