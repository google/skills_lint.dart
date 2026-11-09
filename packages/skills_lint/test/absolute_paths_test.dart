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

const String _skillName = 'test-skill';
final String _frontmatter = buildFrontmatter(name: _skillName);

typedef _SymlinkedSkill = ({
  String linkedRoot,
  Directory realSkillDir,
  Directory linkedSkillDir,
  File realGuide,
  String linkedGuide,
});

/// Creates a directory symlink at [link] pointing to [target], calling
/// [markTestSkipped] and returning `false` when the platform refuses (for
/// example on Windows without Developer Mode).
bool _linkOrSkip(String link, String target) {
  try {
    Link(link).createSync(target);
    return true;
  } on FileSystemException {
    markTestSkipped('This platform cannot create a directory symlink here.');
    return false;
  }
}

/// Builds a skill tree under `real/` and a directory symlink `linked -> real`,
/// or returns `null` after skipping the test when symlinks are unavailable.
Future<_SymlinkedSkill?> _createSymlinkedSkill(Directory root) async {
  final Directory realRoot = await Directory(p.join(root.path, 'real')).create();
  final String linkedRoot = p.join(root.path, 'linked');
  if (!_linkOrSkip(linkedRoot, realRoot.path)) {
    return null;
  }
  final String physicalRoot = realRoot.resolveSymbolicLinksSync();
  final Directory skillsDir = await Directory(p.join(physicalRoot, 'skills')).create();
  final Directory realSkillDir = await createDummySkill(
    skillsDir,
    name: _skillName,
    skillContent: _frontmatter,
  );
  await Directory(p.join(realSkillDir.path, 'references')).create();
  final realGuide = File(p.join(realSkillDir.path, 'references', 'guide.md'));
  await realGuide.writeAsString('Guide\n');
  return (
    linkedRoot: linkedRoot,
    realSkillDir: realSkillDir,
    linkedSkillDir: Directory(p.join(linkedRoot, 'skills', _skillName)),
    realGuide: realGuide,
    linkedGuide: p.join(linkedRoot, 'skills', _skillName, 'references', 'guide.md'),
  );
}

/// Writes [fixedContent] to `SKILL.md` in [skillDir] and validates that
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
  _expectClean(await validator.validate(skillDir), content: fixedContent);
}

/// Runs `skills_lint --ignore-config --fix` with [arguments] and expects exit
/// code 0.
Future<void> _runCliFix(List<String> arguments, {String? workingDirectory}) async {
  final TestProcess process = await startCli([
    '--ignore-config',
    ...arguments,
    '--fix',
  ], workingDirectory: workingDirectory);
  await process.shouldExit(0);
}

void _expectClean(ValidationResult result, {String? content}) {
  final String? reason = content != null ? 'Fixed content:\n$content' : null;
  expect(result.isValid, isTrue, reason: reason);
  expect(result.errors, isEmpty, reason: reason);
  expect(result.warnings, isEmpty, reason: reason);
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

    Future<ValidationResult> validateBody(
      String body, {
      Map<String, RuleConfig>? ruleConfigs,
    }) async {
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: _skillName,
        skillContent: '$_frontmatter$body',
      );
      return Validator(ruleConfigs: ruleConfigs).validate(skillDir);
    }

    void expectWarning(ValidationResult result, String expectedSubstring) {
      expect(result.isValid, isTrue); // Warnings don't fail validation
      expect(result.errors, isEmpty);
      expect(result.warnings, contains(contains(expectedSubstring)));
    }

    test('flags absolute path starting with / as warning by default', () async {
      final ValidationResult result = await validateBody('[Absolute link](/absolute/path.md)\n');
      expectWarning(result, 'Absolute filepath found in link: /absolute/path.md');
    });

    test('flags windows absolute path starting with drive letter as error', () async {
      final ValidationResult result = await validateBody(
        '[Windows absolute link](C:\\absolute\\path.md)\n',
      );
      expectWarning(result, r'Absolute filepath found in link: C:\absolute\path.md');
    });

    test('names the link destination, without its title, as the subject', () async {
      final ValidationResult result = await validateBody(
        '[Absolute link](/absolute/path.md "Title")\n',
      );
      expect(result.validationErrors.map((e) => e.subject), ['/absolute/path.md']);
    });

    for (final (String description, String body, Map<String, RuleConfig> ruleConfigs) in [
      (
        'ignores valid relative paths resembling windows drives',
        '[Relative link](C:relative.md)\n',
        {RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled)},
      ),
      (
        'ignores ordinary file links',
        '[Relative link](file.md)\n',
        {RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled)},
      ),
      (
        'ignores absolute paths when disabled',
        'Body with [broken link](missing.md) and [absolute link](/absolute/path.md)',
        {AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled)},
      ),
    ]) {
      test(description, () async {
        _expectClean(await validateBody(body, ruleConfigs: ruleConfigs));
      });
    }

    test(
      'flags absolute path as warning when absolutePathsSeverity: AnalysisSeverity.warning',
      () async {
        final ValidationResult result = await validateBody(
          'Body with [absolute link](/absolute/path.md)',
          ruleConfigs: {
            AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
          },
        );
        expectWarning(result, 'Absolute filepath found in link: /absolute/path.md');
      },
    );

    test('reports accurate 1-based line number for absolute path link', () async {
      final Directory skillDir = await Directory(p.join(tempDir.path, _skillName)).create();
      const raw =
          '---\n'
          'name: test-skill\n'
          'description: A test skill\n'
          '---\n'
          '\n'
          'Line 5 content\n'
          'Line 6 has [broken absolute link](/abs/path/file.md).\n';
      final List<ValidationError> errors = await AbsolutePathsRule().validate(
        SkillContext(directory: skillDir, rawContent: raw),
      );
      expect(errors, hasLength(1));
      expect(errors.single.ruleId, 'check-absolute-paths');
      expect(errors.single.region?.startLine, 7);
    });

    _defineFixTests(() => tempDir);
  });

  defineCliTests();
}

/// Defines the unit tests of [AbsolutePathsRule.fix].
void _defineFixTests(Directory Function() currentTempDir) {
  Future<String> fixBody(String body, {Directory? directory}) async {
    final Directory skillDir =
        directory ??
        await Directory(p.join(currentTempDir().path, _skillName)).create(recursive: true);
    return AbsolutePathsRule().fix(
      SkillContext(directory: skillDir, rawContent: '$_frontmatter$body'),
    );
  }

  for (final (String description, String suffix, String expectedLink) in [
    ('fixes absolute path to relative if file exists', '', '(../target.md)'),
    (
      'fixes absolute path with title to relative preserving title',
      ' "Target Title"',
      '(../target.md "Target Title")',
    ),
  ]) {
    test(description, () async {
      final File targetFile = await File(p.join(currentTempDir().path, 'target.md')).create();
      final String fixedContent = await fixBody('[Link](${targetFile.path}$suffix)\n');
      expect(fixedContent, contains(expectedLink));
    });
  }

  for (final title in ['"see (note)"', "'see (note)'", '(see note)']) {
    test('preserves title $title when fixing an absolute link', () async {
      final Directory tempDir = currentTempDir();
      final Directory skillDir = await Directory(p.join(tempDir.path, _skillName)).create();
      final File targetFile = await File(p.join(tempDir.path, 'target.md')).create();
      final expected = '${_frontmatter}See [Link (label)](../target.md $title) now.\n';
      final String fixed = await fixBody(
        'See [Link (label)](${targetFile.path} $title) now.\n',
        directory: skillDir,
      );
      expect(fixed, expected);
      expect(
        await AbsolutePathsRule().fix(SkillContext(directory: skillDir, rawContent: fixed)),
        expected,
      );
    });
  }

  test('does not fix absolute path if file does not exist', () async {
    final String fixedContent = await fixBody('[Link](/non/existent/file.md)\n');
    expect(fixedContent, contains('(/non/existent/file.md)'));
  });

  for (final (
        String description,
        Directory Function(_SymlinkedSkill) pickSkillDir,
        String Function(_SymlinkedSkill) pickTarget,
      )
      in [
        (
          'rewrites a link that goes through a symlink to a path inside the skill directory',
          (_SymlinkedSkill f) => f.realSkillDir,
          (_SymlinkedSkill f) => f.linkedGuide,
        ),
        (
          'rewrites a link that names the physical path when the skill directory is opened through a symlink',
          (_SymlinkedSkill f) => f.linkedSkillDir,
          (_SymlinkedSkill f) => f.realGuide.path,
        ),
      ]) {
    test(description, () async {
      final _SymlinkedSkill? fixture = await _createSymlinkedSkill(currentTempDir());
      if (fixture == null) {
        return;
      }
      final Directory skillDir = pickSkillDir(fixture);
      final String fixed = await fixBody(
        'See [guide](${pickTarget(fixture)}).\n',
        directory: skillDir,
      );
      await _expectPortableInSkillRoundTrip(skillDir, fixed);
      expect(fixed, contains('(references/guide.md)'));
    });
  }

  test(
    'rewrites an outside link lexically when the skill directory is a symlink at a different depth',
    () async {
      final String root = currentTempDir().resolveSymbolicLinksSync();
      await Directory(p.join(root, 'repo', 'skills')).create(recursive: true);
      final repoReadme = File(p.join(root, 'repo', 'README.md'));
      await repoReadme.writeAsString('Readme\n');
      final Directory storeParent = await Directory(
        p.join(root, 'store', 'a', 'b', 'c'),
      ).create(recursive: true);
      final Directory storeSkill = await createDummySkill(
        storeParent,
        name: _skillName,
        skillContent: _frontmatter,
      );
      final linkedSkillDir = Directory(p.join(root, 'repo', 'skills', _skillName));
      if (!_linkOrSkip(linkedSkillDir.path, storeSkill.path)) {
        return;
      }

      final String fixed = await fixBody(
        'See [readme](${repoReadme.path}).\n',
        directory: linkedSkillDir,
      );
      expect(fixed, contains('(../../README.md)'));

      await File(p.join(linkedSkillDir.path, 'SKILL.md')).writeAsString(fixed);
      final ValidationResult roundTrip = await Validator(
        ruleConfigs: {
          AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.error),
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.error),
        },
      ).validate(linkedSkillDir);
      _expectClean(roundTrip, content: fixed);
    },
  );
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  test('--fix preserves a parenthesized link title on repeated runs', () async {
    await withTempDir((tempDir) async {
      final File targetFile = await File(p.join(tempDir.path, 'target.md')).create();
      final Directory skillDir = await createDummySkill(
        tempDir,
        name: _skillName,
        skillContent: '${_frontmatter}See [t](${targetFile.path} "see (note)") now.\n',
      );
      final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
      final expected = '${_frontmatter}See [t](../target.md "see (note)") now.\n';
      for (var run = 1; run <= 2; run++) {
        await _runCliFix(['-s', skillDir.path]);
        expect(await skillFile.readAsString(), expected, reason: 'After --fix run $run');
      }
    });
  });

  test(
    '--fix writes an in-skill relative link when invoked from a symlinked working directory',
    () async {
      await withTempDir((tempDir) async {
        final _SymlinkedSkill? fixture = await _createSymlinkedSkill(tempDir);
        if (fixture == null) {
          return;
        }
        final skillFile = File(p.join(fixture.realSkillDir.path, 'SKILL.md'));
        await skillFile.writeAsString('${_frontmatter}See [guide](${fixture.linkedGuide}).\n');

        await _runCliFix([
          '-s',
          p.join('skills', _skillName),
          '--check-absolute-paths',
          '--check-relative-paths',
          '--check-relative-paths-within-skill=true',
        ], workingDirectory: fixture.linkedRoot);
        final String fixed = await skillFile.readAsString();
        expect(fixed, '${_frontmatter}See [guide](references/guide.md).\n');
        await _expectPortableInSkillRoundTrip(fixture.realSkillDir, fixed);
      });
    },
  );
}
