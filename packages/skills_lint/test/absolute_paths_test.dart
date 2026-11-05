// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';

import 'package:skills_lint/src/rules/absolute_paths_rule.dart';
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

/// Creates a directory symlink at [link] pointing to [target], returning
/// `false` when this platform cannot create one here (for example on Windows
/// without Developer Mode).
bool _tryCreateLink(String link, String target) {
  try {
    Link(link).createSync(target);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Writes [fixedContent] to `SKILL.md` in [skillDir] and validates that both
/// `check-absolute-paths` and `check-relative-paths` (`within-skill: true`)
/// report zero diagnostics.
Future<void> _expectPortableInSkillRoundTrip(Directory skillDir, String fixedContent) async {
  await File(p.join(skillDir.path, 'SKILL.md')).writeAsString(fixedContent);
  final validator = Validator(
    ruleConfigs: {
      AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.error),
      RelativePathsRule.ruleName: RuleConfig(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {RelativePathsRule.withinSkillParameter: true}),
      ),
    },
  );
  final ValidationResult roundTrip = await validator.validate(skillDir);
  expect(roundTrip.errors, isEmpty, reason: 'Fixed content:\n$fixedContent');
  expect(roundTrip.warnings, isEmpty, reason: 'Fixed content:\n$fixedContent');
}

void main() {
  group('Absolute Paths Validation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('absolute_path_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('flags absolute path starting with / as warning by default', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Absolute link](/absolute/path.md)\n',
      );

      final validator = Validator();
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(
        result.warnings,
        contains(contains('Absolute filepath found in link: /absolute/path.md')),
      );
    });

    test('flags windows absolute path starting with drive letter as error', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Windows absolute link](C:\\absolute\\path.md)\n',
      );

      final validator = Validator();
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(
        result.warnings,
        contains(contains(r'Absolute filepath found in link: C:\absolute\path.md')),
      );
    });

    test('names the link destination, without its title, as the subject', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Absolute link](/absolute/path.md "Title")\n',
      );

      final ValidationResult result = await Validator().validate(skillDir);

      expect(result.validationErrors.map((e) => e.subject), ['/absolute/path.md']);
    });

    test('ignores valid relative paths resembling windows drives', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Relative link](C:relative.md)\n');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('ignores ordinary file links', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Relative link](file.md)\n');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });
    test('ignores absolute paths when disabled', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}Body with [broken link](missing.md) and [absolute link](/absolute/path.md)',
      );

      final validator = Validator(
        ruleConfigs: {
          AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test(
      'flags absolute path as warning when absolutePathsSeverity: AnalysisSeverity.warning',
      () async {
        final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
        await File('${skillDir.path}/SKILL.md').writeAsString(
          '${buildFrontmatter(name: 'test-skill')}Body with [absolute link](/absolute/path.md)',
        );

        final validator = Validator(
          ruleConfigs: {
            AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
          },
        );
        final ValidationResult result = await validator.validate(skillDir);

        expect(result.isValid, isTrue); // Warnings don't fail validation
        expect(result.errors, isEmpty);
        expect(
          result.warnings,
          contains(contains('Absolute filepath found in link: /absolute/path.md')),
        );
      },
    );

    test('fixes absolute path to relative if file exists', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      final File targetFile = await File('${tempDir.path}/target.md').create();

      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](${targetFile.path})\n');

      final rule = AbsolutePathsRule();
      final file = File('${skillDir.path}/SKILL.md');
      final String content = await file.readAsString();
      final context = SkillContext(directory: skillDir, rawContent: content);

      final String fixedContent = await rule.fix(
        SkillContext(directory: context.directory, rawContent: content),
      );

      expect(fixedContent, contains('(../target.md)'));
    });

    test('fixes absolute path with title to relative preserving title', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      final File targetFile = await File('${tempDir.path}/target.md').create();

      final rule = AbsolutePathsRule();
      final content =
          '${buildFrontmatter(name: 'test-skill')}[Link](${targetFile.path} "Target Title")\n';
      final String fixedContent = await rule.fix(
        SkillContext(directory: skillDir, rawContent: content),
      );

      expect(fixedContent, contains('(../target.md "Target Title")'));
    });

    for (final title in ['"see (note)"', "'see (note)'", '(see note)']) {
      test('preserves title $title when fixing an absolute link', () async {
        final Directory skillDir = await Directory(p.join(tempDir.path, 'test-skill')).create();
        final File targetFile = await File(p.join(tempDir.path, 'target.md')).create();
        final String frontmatter = buildFrontmatter(name: 'test-skill');
        final content = '${frontmatter}See [Link (label)](${targetFile.path} $title) now.\n';
        final expected = '${frontmatter}See [Link (label)](../target.md $title) now.\n';
        final rule = AbsolutePathsRule();
        final String fixed = await rule.fix(SkillContext(directory: skillDir, rawContent: content));
        expect(fixed, expected);
        expect(await rule.fix(SkillContext(directory: skillDir, rawContent: fixed)), expected);
      });
    }

    test('does not fix absolute path if file does not exist', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();

      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](/non/existent/file.md)\n');

      final rule = AbsolutePathsRule();
      final file = File('${skillDir.path}/SKILL.md');
      final String content = await file.readAsString();
      final context = SkillContext(directory: skillDir, rawContent: content);

      final String fixedContent = await rule.fix(
        SkillContext(directory: context.directory, rawContent: content),
      );

      expect(fixedContent, contains('(/non/existent/file.md)'));
    });
    test('reports accurate 1-based line number for absolute path link', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '---\n'
        'name: test-skill\n'
        'description: A test skill\n'
        '---\n'
        '\n'
        'Line 5 content\n'
        'Line 6 has [broken absolute link](/abs/path/file.md).\n',
      );

      final rule = AbsolutePathsRule();
      final file = File('${skillDir.path}/SKILL.md');
      final String raw = await file.readAsString();
      final context = SkillContext(directory: skillDir, rawContent: raw);

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors.length, equals(1));
      expect(errors.first.ruleId, equals('check-absolute-paths'));
      expect(errors.first.region?.startLine, equals(7));
    });

    test(
      'rewrites a link that goes through a symlink to a path inside the skill directory',
      () async {
        final Directory realRoot = await Directory(p.join(tempDir.path, 'real')).create();
        final String linkedRoot = p.join(tempDir.path, 'linked');
        if (!_tryCreateLink(linkedRoot, realRoot.path)) {
          markTestSkipped('This platform cannot create a directory symlink here.');
          return;
        }
        final Directory realSkillDir = await Directory(
          p.join(realRoot.resolveSymbolicLinksSync(), 'skills', 'test-skill'),
        ).create(recursive: true);
        await Directory(p.join(realSkillDir.path, 'references')).create();
        await File(p.join(realSkillDir.path, 'references', 'guide.md')).writeAsString('Guide\n');

        final String symlinkedTarget = p.join(
          linkedRoot,
          'skills',
          'test-skill',
          'references',
          'guide.md',
        );
        final content = '${buildFrontmatter(name: 'test-skill')}See [guide]($symlinkedTarget).\n';
        final String fixed = await AbsolutePathsRule().fix(
          SkillContext(directory: realSkillDir, rawContent: content),
        );

        await _expectPortableInSkillRoundTrip(realSkillDir, fixed);
        expect(fixed, contains('(references/guide.md)'));
      },
    );

    test(
      'rewrites a link to the physical path when the skill directory is opened through a symlink',
      () async {
        final Directory realRoot = await Directory(p.join(tempDir.path, 'real')).create();
        final String linkedRoot = p.join(tempDir.path, 'linked');
        if (!_tryCreateLink(linkedRoot, realRoot.path)) {
          markTestSkipped('This platform cannot create a directory symlink here.');
          return;
        }
        final Directory realSkillDir = await Directory(
          p.join(realRoot.resolveSymbolicLinksSync(), 'skills', 'test-skill'),
        ).create(recursive: true);
        await Directory(p.join(realSkillDir.path, 'references')).create();
        final File realGuide = await File(
          p.join(realSkillDir.path, 'references', 'guide.md'),
        ).create();
        await realGuide.writeAsString('Guide\n');

        final linkedSkillDir = Directory(p.join(linkedRoot, 'skills', 'test-skill'));
        final content = '${buildFrontmatter(name: 'test-skill')}See [guide](${realGuide.path}).\n';
        final String fixed = await AbsolutePathsRule().fix(
          SkillContext(directory: linkedSkillDir, rawContent: content),
        );

        await _expectPortableInSkillRoundTrip(linkedSkillDir, fixed);
        expect(fixed, contains('(references/guide.md)'));
      },
    );
  });

  defineCliTests();
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  test('--fix preserves a parenthesized link title on repeated runs', () async {
    await withTempDir((tempDir) async {
      final Directory skillDir = await Directory(p.join(tempDir.path, 'test-skill')).create();
      final File targetFile = await File(p.join(tempDir.path, 'target.md')).create();
      final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
      final String frontmatter = buildFrontmatter(name: 'test-skill');
      await skillFile.writeAsString(
        '${frontmatter}See [t](${targetFile.path} "see (note)") now.\n',
      );
      final expected = '${frontmatter}See [t](../target.md "see (note)") now.\n';
      for (var run = 1; run <= 2; run++) {
        final TestProcess process = await startCli([
          '--ignore-config',
          '-s',
          skillDir.path,
          '--fix',
        ]);
        await process.shouldExit(0);
        expect(await skillFile.readAsString(), expected, reason: 'After --fix run $run');
      }
    });
  });

  test(
    '--fix writes an in-skill relative link when invoked from a symlinked working directory',
    () async {
      await withTempDir((tempDir) async {
        final Directory realRoot = await Directory(p.join(tempDir.path, 'real')).create();
        final String linkedRoot = p.join(tempDir.path, 'linked');
        if (!_tryCreateLink(linkedRoot, realRoot.path)) {
          markTestSkipped('This platform cannot create a directory symlink here.');
          return;
        }
        final Directory skillDir = await Directory(
          p.join(realRoot.path, 'skills', 'my-skill'),
        ).create(recursive: true);
        await Directory(p.join(skillDir.path, 'references')).create();
        await File(p.join(skillDir.path, 'references', 'guide.md')).writeAsString('Guide\n');
        final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
        final String symlinkedGuide = p.join(
          linkedRoot,
          'skills',
          'my-skill',
          'references',
          'guide.md',
        );
        final String frontmatter = buildFrontmatter(name: 'my-skill');
        await skillFile.writeAsString('${frontmatter}See [guide]($symlinkedGuide).\n');

        final TestProcess fixProcess = await startCli([
          '--ignore-config',
          '-s',
          p.join('skills', 'my-skill'),
          '--check-absolute-paths',
          '--check-relative-paths',
          '--check-relative-paths-within-skill=true',
          '--fix',
        ], workingDirectory: linkedRoot);
        await fixProcess.shouldExit(0);
        expect(await skillFile.readAsString(), '${frontmatter}See [guide](references/guide.md).\n');
      });
    },
  );
}
