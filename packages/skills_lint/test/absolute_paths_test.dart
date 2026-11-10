// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/markdown_links.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/absolute_paths_rule.dart';
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:skills_lint/src/skill_links.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

const String _skillName = 'test-skill';
final String _frontmatter = buildFrontmatter(name: _skillName);

/// Logical (under `linked/`) and physical (under `real/`) paths for the skill
/// directory and `references/guide.md` created by [_createSymlinkedSkill].
typedef _SymlinkedSkill = ({String linkedRoot, SkillPathPair skillDir, SkillPathPair guide});

/// Creates a directory symlink at [linkPath] pointing to [targetPath] and
/// asserts that the symlink exists and resolves to [targetPath].
void _createDirectorySymlink(String linkPath, String targetPath) {
  // Real filesystem symlinks are needed because AbsolutePathsRule.fix calls
  // dart:io's FileSystemEntity.resolveSymbolicLinksSync directly; see
  // https://github.com/google/skills_lint.dart/issues/188.
  try {
    Link(linkPath).createSync(targetPath);
  } on FileSystemException catch (error) {
    fail(
      'Creating a symlink failed on ${Platform.operatingSystem} ($error); '
      'this test needs symlink support (on Windows, Developer Mode or admin).',
    );
  }
  expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
  final String resolvedLink = Directory(linkPath).resolveSymbolicLinksSync();
  expect(p.equals(resolvedLink, linkPath), isFalse);
  expect(p.equals(resolvedLink, Directory(targetPath).resolveSymbolicLinksSync()), isTrue);
}

/// Creates a test skill with `references/guide.md` under `<root>/real` and a
/// directory symlink `<root>/linked` pointing to `<root>/real`.
Future<_SymlinkedSkill> _createSymlinkedSkill(Directory root) async {
  final Directory realRoot = await Directory(p.join(root.path, 'real')).create();
  final String linkedRoot = p.join(root.path, 'linked');
  _createDirectorySymlink(linkedRoot, realRoot.path);
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
  final String linkedSkillPath = p.join(linkedRoot, 'skills', _skillName);
  return (
    linkedRoot: linkedRoot,
    skillDir: (logical: linkedSkillPath, physical: realSkillDir.path),
    guide: (logical: p.join(linkedSkillPath, 'references', 'guide.md'), physical: realGuide.path),
  );
}

/// Validates [fixedContent] in memory as `SKILL.md` in [skillDir] with
/// [AbsolutePathsRule] at error severity, and extracts the single Markdown link
/// destination resolved lexically from [skillDir].
Future<String> _validateAndResolveSingleLink(Directory skillDir, String fixedContent) async {
  final reason = 'Fixed content:\n$fixedContent';
  final validator = Validator(
    ruleConfigs: {AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.error)},
  );
  final context = SkillContext(directory: skillDir, rawContent: fixedContent);
  final ValidationResult result = await validator.validateProposedContent(context, fixedContent);
  expect(result, hasNoErrorsOrWarnings, reason: reason);

  final List<MarkdownLink> links = bodyLinksOf(context);
  expect(links, hasLength(1), reason: reason);
  return p.normalize(p.join(skillDir.path, links.single.target));
}

/// Validates [fixedContent] in [skillDir] and asserts that its single link
/// stays lexically inside [skillDir] and resolves to [expectedTarget].
Future<void> _expectFixedInSkillLink(
  Directory skillDir,
  String fixedContent, {
  required File expectedTarget,
}) async {
  final reason = 'Fixed content:\n$fixedContent';
  final String resolved = await _validateAndResolveSingleLink(skillDir, fixedContent);
  expect(p.isWithin(skillDir.path, resolved), isTrue, reason: reason);
  expect(File(resolved).existsSync(), isTrue, reason: reason);
  expect(
    p.equals(File(resolved).resolveSymbolicLinksSync(), expectedTarget.resolveSymbolicLinksSync()),
    isTrue,
    reason: reason,
  );
}

void main() {
  group('Markdown syntax', () {
    test('ignores absolute paths in code spans and code blocks', () async {
      await withTempDir((tempDir) async {
        final Directory skillDir = await Directory(p.join(tempDir.path, 'test-skill')).create();
        final String target = (await File(p.join(tempDir.path, 'target.md')).create()).path;
        final content =
            '${buildFrontmatter(name: 'test-skill')}'
            'Write `[a]($target)`.\n'
            '\n'
            '```\n'
            '[b]($target)\n'
            '```\n';
        final context = SkillContext(directory: skillDir, rawContent: content);

        expect(await AbsolutePathsRule().validate(context), isEmpty);
        expect(await AbsolutePathsRule().fix(context), content);
      });
    });

    test('reports and fixes angle-bracket and parenthesized destinations', () async {
      await withTempDir((tempDir) async {
        final Directory skillDir = await Directory(p.join(tempDir.path, 'test-skill')).create();
        final String spaced = (await File(p.join(tempDir.path, 'my file.md')).create()).path;
        final String parens = (await File(p.join(tempDir.path, 'a(b).md')).create()).path;
        final String logo = (await File(p.join(tempDir.path, 'logo.png')).create()).path;
        final String frontmatter = buildFrontmatter(name: 'test-skill');
        final content =
            '$frontmatter[a](<$spaced> "t") [b]($parens)\n'
            '[![logo]($logo)]($parens)\n';
        final rule = AbsolutePathsRule();

        final List<ValidationError> errors = await rule.validate(
          SkillContext(directory: skillDir, rawContent: content),
        );
        final String fixed = await rule.fix(SkillContext(directory: skillDir, rawContent: content));

        expect(errors.map((e) => e.subject), [spaced, parens, logo, parens]);
        expect(
          fixed,
          '$frontmatter[a](<../my file.md> "t") [b](<../a(b).md>)\n'
          '[![logo](../logo.png)](<../a(b).md>)\n',
        );
        final fixedContext = SkillContext(directory: skillDir, rawContent: fixed);
        expect(await rule.validate(fixedContext), isEmpty);
        expect(await rule.fix(fixedContext), fixed);
        expect(await RelativePathsRule().validate(fixedContext), isEmpty);
      });
    });

    test(
      'reports and fixes reference-style links sharing a definition, respecting ignoredSubjects',
      () async {
        await withTempDir((tempDir) async {
          final Directory skillDir = await Directory(p.join(tempDir.path, 'test-skill')).create();
          final String guide = (await File(p.join(tempDir.path, 'my guide.md')).create()).path;
          final String kept = (await File(p.join(tempDir.path, 'kept.md')).create()).path;
          final String frontmatter = buildFrontmatter(name: 'test-skill');
          final content =
              '${frontmatter}See [first][guide], [guide][], and [kept].\n'
              '\n'
              '[guide]: <$guide> "Guide"\n'
              '[kept]: $kept\n';
          final rule = AbsolutePathsRule();
          final context = SkillContext(directory: skillDir, rawContent: content);

          final List<ValidationError> errors = await rule.validate(context);
          expect(errors.map((e) => e.subject), [guide, guide, kept]);

          final String fixed = await rule.fix(context, ignoredSubjects: {kept});
          expect(
            fixed,
            '${frontmatter}See [first][guide], [guide][], and [kept].\n'
            '\n'
            '[guide]: <../my guide.md> "Guide"\n'
            '[kept]: $kept\n',
          );
          final fixedContext = SkillContext(directory: skillDir, rawContent: fixed);
          final List<ValidationError> remaining = await rule.validate(fixedContext);
          expect(remaining.map((e) => e.subject), [kept]);
          expect(await rule.fix(fixedContext, ignoredSubjects: {kept}), fixed);
          expect(await RelativePathsRule().validate(fixedContext), isEmpty);
        });
      },
    );
  });

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

    /// Asserts that [result] is valid without errors and reports a
    /// `check-absolute-paths` warning whose subject and message carry
    /// [expectedPath].
    void expectAbsolutePathWarning(ValidationResult result, String expectedPath) {
      // Warnings don't fail validation; see
      // https://github.com/google/skills_lint.dart/issues/140.
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(
        result.validationErrors,
        contains(
          isA<ValidationError>()
              .having((ValidationError e) => e.ruleId, 'ruleId', 'check-absolute-paths')
              .having((ValidationError e) => e.severity, 'severity', AnalysisSeverity.warning)
              .having((ValidationError e) => e.subject, 'subject', expectedPath)
              .having((ValidationError e) => e.message, 'message', contains(expectedPath)),
        ),
      );
    }

    test('flags absolute path starting with / as warning by default', () async {
      final ValidationResult result = await writeAndValidateSkill(
        tempDir,
        body: '[Absolute link](/absolute/path.md)\n',
      );
      expectAbsolutePathWarning(result, '/absolute/path.md');
    });

    test('flags windows absolute path starting with drive letter as warning by default', () async {
      final ValidationResult result = await writeAndValidateSkill(
        tempDir,
        body:
            r'[Windows absolute link](C:\absolute\path.md)'
            '\n',
      );
      expectAbsolutePathWarning(result, r'C:\absolute\path.md');
    });

    test('names the link destination, without its title, as the subject', () async {
      final ValidationResult result = await writeAndValidateSkill(
        tempDir,
        body: '[Absolute link](/absolute/path.md "Title")\n',
      );
      expect(result.validationErrors.map((e) => e.subject), ['/absolute/path.md']);
    });

    test('ignores valid relative paths resembling windows drives', () async {
      final ValidationResult result = await writeAndValidateSkill(
        tempDir,
        body: '[Relative link](C:relative.md)\n',
      );
      expect(result, hasNoErrorsOrWarnings);
    });

    test('ignores ordinary file links', () async {
      final ValidationResult result = await writeAndValidateSkill(
        tempDir,
        body: '[Relative link](file.md)\n',
      );
      expect(result, hasNoErrorsOrWarnings);
    });

    test('ignores absolute paths when disabled', () async {
      final ValidationResult result = await writeAndValidateSkill(
        tempDir,
        body: 'Body with [broken link](missing.md) and [absolute link](/absolute/path.md)',
        ruleConfigs: {
          AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.disabled),
        },
      );
      expect(result, hasNoErrorsOrWarnings);
    });

    test(
      'flags absolute path as warning when absolutePathsSeverity: AnalysisSeverity.warning',
      () async {
        final ValidationResult result = await writeAndValidateSkill(
          tempDir,
          body: 'Body with [absolute link](/absolute/path.md)',
          ruleConfigs: {
            AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
          },
        );
        expectAbsolutePathWarning(result, '/absolute/path.md');
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

    /// Runs [AbsolutePathsRule.fix] on valid frontmatter followed by [body] in
    /// [directory] (or a fresh skill directory under [tempDir]).
    Future<String> fixBody(String body, {Directory? directory}) async {
      final Directory skillDir =
          directory ?? await Directory(p.join(tempDir.path, _skillName)).create(recursive: true);
      return AbsolutePathsRule().fix(
        SkillContext(directory: skillDir, rawContent: '$_frontmatter$body'),
      );
    }

    /// Asserts that [AbsolutePathsRule.fix] rewrites an absolute link carrying
    /// [title] to a relative link and preserves [title] across repeated runs.
    Future<void> expectPreservesTitle(String title) async {
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
    }

    test('fixes absolute path to relative if file exists', () async {
      final File targetFile = await File(p.join(tempDir.path, 'target.md')).create();
      final String fixedContent = await fixBody('[Link](${targetFile.path})\n');
      expect(fixedContent, contains('(../target.md)'));
    });

    test('fixes absolute path with title to relative preserving title', () async {
      final File targetFile = await File(p.join(tempDir.path, 'target.md')).create();
      final String fixedContent = await fixBody('[Link](${targetFile.path} "Target Title")\n');
      expect(fixedContent, contains('(../target.md "Target Title")'));
    });

    test('preserves double-quoted title with parentheses when fixing an absolute link', () async {
      await expectPreservesTitle('"see (note)"');
    });

    test('preserves single-quoted title with parentheses when fixing an absolute link', () async {
      await expectPreservesTitle("'see (note)'");
    });

    test('preserves parenthesized title when fixing an absolute link', () async {
      await expectPreservesTitle('(see note)');
    });

    test('does not fix absolute path if file does not exist', () async {
      final String fixedContent = await fixBody('[Link](/non/existent/file.md)\n');
      expect(fixedContent, contains('(/non/existent/file.md)'));
    });

    test(
      'rewrites a link that goes through a symlink to a path inside the skill directory',
      () async {
        final _SymlinkedSkill fixture = await _createSymlinkedSkill(tempDir);
        final realSkillDir = Directory(fixture.skillDir.physical);
        final String fixed = await fixBody(
          'See [guide](${fixture.guide.logical}).\n',
          directory: realSkillDir,
        );
        expect(fixed, contains('(references/guide.md)'));
        await _expectFixedInSkillLink(
          realSkillDir,
          fixed,
          expectedTarget: File(fixture.guide.physical),
        );
      },
    );

    test(
      'rewrites a link that names the physical path when the skill directory is opened through a symlink',
      () async {
        final _SymlinkedSkill fixture = await _createSymlinkedSkill(tempDir);
        final linkedSkillDir = Directory(fixture.skillDir.logical);
        final String fixed = await fixBody(
          'See [guide](${fixture.guide.physical}).\n',
          directory: linkedSkillDir,
        );
        expect(fixed, contains('(references/guide.md)'));
        await _expectFixedInSkillLink(
          linkedSkillDir,
          fixed,
          expectedTarget: File(fixture.guide.physical),
        );
      },
    );

    test(
      'rewrites an outside link lexically when the skill directory is a symlink at a different depth',
      () async {
        final String root = tempDir.resolveSymbolicLinksSync();
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
        _createDirectorySymlink(linkedSkillDir.path, storeSkill.path);

        final String fixed = await fixBody(
          'See [readme](${repoReadme.path}).\n',
          directory: linkedSkillDir,
        );
        expect(fixed, contains('(../../README.md)'));
        final String resolved = await _validateAndResolveSingleLink(linkedSkillDir, fixed);
        expect(p.equals(resolved, repoReadme.path), isTrue, reason: 'Fixed content:\n$fixed');
        expect(File(resolved).existsSync(), isTrue, reason: 'Fixed content:\n$fixed');
      },
    );

    test('fix leaves the links whose target is an ignored subject unchanged', () async {
      final Directory skillDir = await Directory(p.join(tempDir.path, _skillName)).create();
      final String kept = (await File(p.join(tempDir.path, 'kept.md')).create()).path;
      final String other = (await File(p.join(tempDir.path, 'other.md')).create()).path;
      final keptLinks = '[A]($kept "a title")\n[B]($kept)\n';
      final content = '$_frontmatter$keptLinks[Other]($other)\n';

      final String fixed = await AbsolutePathsRule().fix(
        SkillContext(directory: skillDir, rawContent: content),
        ignoredSubjects: {kept},
      );

      expect(fixed, '$_frontmatter$keptLinks[Other](../other.md)\n');
      final List<ValidationError> remaining = await AbsolutePathsRule().validate(
        SkillContext(directory: skillDir, rawContent: fixed),
      );
      expect(remaining.map((e) => e.subject), [kept, kept]);
    });
  });

  group('AbsolutePathsRule.relativeSkillLink', () {
    test('normalizes Windows backslashes to forward slashes for an in-skill link', () {
      const skill = r'C:\real\skills\test-skill';
      const target = r'C:\real\skills\test-skill\references\guide.md';
      final String link = AbsolutePathsRule.relativeSkillLink(
        skillDirectory: (logical: skill, physical: skill),
        targetFile: (logical: r'C:\linked\skills\test-skill\references\guide.md', physical: target),
        pathContext: p.windows,
      );
      expect(link, 'references/guide.md');
    });

    test('resolves a Windows symlinked skill directory against a physical link path', () {
      const target = r'C:\real\skills\test-skill\references\guide.md';
      final String link = AbsolutePathsRule.relativeSkillLink(
        skillDirectory: (
          logical: r'C:\linked\skills\test-skill',
          physical: r'C:\real\skills\test-skill',
        ),
        targetFile: (logical: target, physical: target),
        pathContext: p.windows,
      );
      expect(link, 'references/guide.md');
    });

    test('handles mixed forward and backslash separators on Windows', () {
      const skill = r'C:\real\skills\test-skill';
      const target = r'C:\real\skills\test-skill\references\nested\guide.md';
      final String link = AbsolutePathsRule.relativeSkillLink(
        skillDirectory: (logical: skill, physical: skill),
        targetFile: (
          logical: 'C:/linked/skills/test-skill/references/nested/guide.md',
          physical: target,
        ),
        pathContext: p.windows,
      );
      expect(link, 'references/nested/guide.md');
    });

    test(
      'uses the logical Windows path with forward slashes for an outside target when a symlinked skill directory changes depth',
      () {
        const target = r'C:\work\repo\docs\README.md';
        final String link = AbsolutePathsRule.relativeSkillLink(
          skillDirectory: (
            logical: r'C:\work\repo\skills\test-skill',
            physical: r'C:\work\store\a\b\c\test-skill',
          ),
          targetFile: (logical: 'C:/work/repo/docs/README.md', physical: target),
          pathContext: p.windows,
        );
        expect(link, '../../docs/README.md');
      },
    );

    test('resolves a POSIX symlinked link path to an in-skill relative path', () {
      const skill = '/private/tmp/work/skills/test-skill';
      const target = '/private/tmp/work/skills/test-skill/references/guide.md';
      final String link = AbsolutePathsRule.relativeSkillLink(
        skillDirectory: (logical: skill, physical: skill),
        targetFile: (logical: '/tmp/work/skills/test-skill/references/guide.md', physical: target),
        pathContext: p.posix,
      );
      expect(link, 'references/guide.md');
    });
  });

  defineCliTests();
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  group('CLI --fix of check-absolute-paths', () {
    Future<({String stdout, String stderr})> run(
      List<String> args, {
      String? workingDirectory,
      int exitCode = 0,
    }) async {
      final TestProcess process = await startCli(args, workingDirectory: workingDirectory);
      final String stdout = await process.stdoutStream().join('\n');
      final String stderr = await process.stderrStream().join('\n');
      await process.shouldExit(exitCode);
      return (stdout: stdout, stderr: stderr);
    }

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

        final (:String stdout, :String stderr) = await run([
          '--ignore-config',
          '-s',
          skillDir.path,
          '--fix',
        ]);
        expect(stderr, isEmpty);
        expect(stdout, contains('Applied fixes for $_skillName'));
        expect(await skillFile.readAsString(), expected, reason: 'After --fix run 1');

        final ({String stdout, String stderr}) secondRun = await run([
          '--ignore-config',
          '-s',
          skillDir.path,
          '--fix',
        ]);
        expect(secondRun.stderr, isEmpty);
        expect(await skillFile.readAsString(), expected, reason: 'After --fix run 2');
      });
    });

    test(
      '--fix writes an in-skill relative link when invoked from a symlinked working directory',
      () async {
        await withTempDir((tempDir) async {
          final _SymlinkedSkill fixture = await _createSymlinkedSkill(tempDir);
          final realSkillDir = Directory(fixture.skillDir.physical);
          final skillFile = File(p.join(realSkillDir.path, 'SKILL.md'));
          await skillFile.writeAsString('${_frontmatter}See [guide](${fixture.guide.logical}).\n');

          final (:String stdout, :String stderr) = await run([
            '--ignore-config',
            '-s',
            p.join('skills', _skillName),
            '--check-absolute-paths',
            '--fix',
          ], workingDirectory: fixture.linkedRoot);
          expect(stderr, isEmpty);
          expect(stdout, contains('Applied fixes for $_skillName'));

          final String fixed = await skillFile.readAsString();
          expect(fixed, '${_frontmatter}See [guide](references/guide.md).\n');
          await _expectFixedInSkillLink(
            realSkillDir,
            fixed,
            expectedTarget: File(fixture.guide.physical),
          );
        });
      },
    );
  });
}
