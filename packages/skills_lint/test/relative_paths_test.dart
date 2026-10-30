// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_parser.dart';
import 'package:skills_lint/src/entry_point.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/absolute_paths_rule.dart';
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

const String _param = RelativePathsRule.withinSkillParameter;
const String _flag = '--${RelativePathsRule.ruleName}-$_param';
const String _outside = 'Linked file is outside the skill directory';
const String _missing = 'Linked file does not exist';

/// Creates a package with two published skills and a file next to them:
///
/// ```text
/// <root>/
///   RULES.md
///   skills/
///     README.md
///     my-skill/
///       SKILL.md        (frontmatter, then [mySkillBody])
///       references/DETAILS.md
///     other-skill/
///       SKILL.md
/// ```
///
/// Returns the `my-skill` directory. Every linked file exists, so a
/// diagnostic about an outside link is never caused by a missing file.
Future<Directory> _createPackage(Directory root, {String mySkillBody = ''}) async {
  final Directory skills = await Directory(p.join(root.path, 'skills')).create();
  final Directory mySkill = await createDummySkill(
    skills,
    name: 'my-skill',
    skillContent: '${buildFrontmatter(name: 'my-skill')}$mySkillBody',
  );
  await Directory(p.join(mySkill.path, 'references')).create();
  await File(p.join(mySkill.path, 'references', 'DETAILS.md')).writeAsString('Details');
  await createDummySkill(
    skills,
    name: 'other-skill',
    skillContent: '${buildFrontmatter(name: 'other-skill')}Body\n',
  );
  await File(p.join(skills.path, 'README.md')).writeAsString('Readme');
  await File(p.join(root.path, 'RULES.md')).writeAsString('Rules');
  return mySkill;
}

void main() {
  group('Relative Paths Validation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('paths_test.');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('passes with valid relative file path (existing file)', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Link to a reference](references/DETAILS.md)\n',
      );

      final Directory refDir = await Directory('${skillDir.path}/references').create();
      await File('${refDir.path}/DETAILS.md').writeAsString('Details here');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('warns with missing relative file path and reports resolved path', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Link to a references file missing](references/MISSING.md)\n',
      );

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.warnings, contains(contains('Linked file does not exist')));
      expect(result.warnings, contains(contains('references/MISSING.md')));
      // The diagnostic includes the resolved absolute path. The exact
      // shape differs by platform (POSIX `/...` vs Windows `C:\...`),
      // so just assert the prefix and that what follows is absolute.
      final String warning = result.warnings.firstWhere((w) => w.contains('resolved to '));
      final int prefixIdx = warning.indexOf('resolved to ');
      final String resolved = warning.substring(prefixIdx + 'resolved to '.length);
      expect(p.isAbsolute(resolved), isTrue, reason: 'resolved path "$resolved" is not absolute');
    });

    test('checks a link that is not a valid URI as a file path', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      // Uri.parse rejects "1a:b.md" (a scheme must start with a letter).
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Odd link](1a:b.md)\n');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.warnings, contains(contains('Linked file does not exist')));
      expect(result.warnings, contains(contains('1a:b.md')));
    });

    test('did-you-mean: suggests near-miss sibling file when one exists', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](references/DEATILS.md)\n');
      final Directory refs = await Directory('${skillDir.path}/references').create();
      await File('${refs.path}/DETAILS.md').writeAsString('Details');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);
      expect(result.isValid, isTrue);
      // Suggestion preserves the link's directory prefix so the user
      // gets back a copy-pasteable replacement, not just a basename.
      expect(result.warnings, contains(contains('Did you mean "references/DETAILS.md"?')));
    });

    test('did-you-mean: stays silent when nothing in the sibling dir is close', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File(
        '${skillDir.path}/SKILL.md',
      ).writeAsString('${buildFrontmatter(name: 'test-skill')}[Link](references/MISSING.md)\n');
      final Directory refs = await Directory('${skillDir.path}/references').create();
      await File('${refs.path}/UNRELATED.txt').writeAsString('Nope');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);
      expect(result.isValid, isTrue);
      expect(result.warnings, contains(contains('Linked file does not exist')));
      expect(result.warnings.any((w) => w.contains('Did you mean')), isFalse);
    });

    test('fails with absolute file path', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Absolute path link](/tmp/some_absolute_path/file.md)\n',
      );

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
          AbsolutePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.error),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('Absolute filepath found in link')));
    });

    // within-skill must skip these links too, so run the same links with it on.
    for (final withinSkill in [false, true]) {
      test('ignores web URLs, emails, javascript, data URIs, and anchors '
          '(${RelativePathsRule.withinSkillParameter}: $withinSkill)', () async {
        final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
        await File('${skillDir.path}/SKILL.md').writeAsString(
          '${buildFrontmatter(name: 'test-skill')}- [Web link](http://example.com)\n- [Web TLS link](https://example.com)\n- [Email link](mailto:user@domain.com)\n- [JS link](javascript:alert(1))\n- [Data URI](data:image/png;base64,iVBORw)\n- [Anchor link](#section-name)\n',
        );

        final validator = Validator(
          ruleConfigs: {
            RelativePathsRule.ruleName: RuleConfig(
              severity: AnalysisSeverity.warning,
              parameters: CustomRuleParameters({
                RelativePathsRule.withinSkillParameter: withinSkill,
              }),
            ),
          },
        );
        final ValidationResult result = await validator.validate(skillDir);

        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
        expect(result.warnings, isEmpty); // None of these should trigger local file checks
      });
    }

    test('passes with valid relative image path and title', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}![Accessible description](images/screenshot.png "Hover description")\n',
      );

      final Directory imgDir = await Directory('${skillDir.path}/images').create();
      await File('${imgDir.path}/screenshot.png').writeAsString('image content');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('passes with relative path containing line fragments', () async {
      final Directory skillDir = await Directory(
        '${tempDir.path}/a/b/c/test-skill',
      ).create(recursive: true);
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Link to lines](../../../CONTRIBUTING.md#L64-L80)\n',
      );

      await File('${tempDir.path}/a/CONTRIBUTING.md').create(recursive: true);

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('passes with relative path containing anchor fragments', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Link to section](styleguide.md#miscellaneous-languages)\n',
      );

      await File('${skillDir.path}/styleguide.md').writeAsString('Styleguide content');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('passes with leading and trailing whitespace in link', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '${buildFrontmatter(name: 'test-skill')}[Link with whitespace]( styleguide.md )\n',
      );

      await File('${skillDir.path}/styleguide.md').writeAsString('Styleguide content');

      final validator = Validator(
        ruleConfigs: {
          RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.warning),
        },
      );
      final ValidationResult result = await validator.validate(skillDir);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('reports accurate 1-based line number for missing relative link', () async {
      final Directory skillDir = await Directory('${tempDir.path}/test-skill').create();
      await File('${skillDir.path}/SKILL.md').writeAsString(
        '---\n'
        'name: test-skill\n'
        'description: A test skill\n'
        '---\n'
        '\n'
        'Some content on line 6\n'
        'Line 7 has [missing link](docs/MISSING.md).\n',
      );

      final rule = RelativePathsRule(severity: AnalysisSeverity.error);
      final file = File('${skillDir.path}/SKILL.md');
      final String raw = await file.readAsString();
      final context = SkillContext(directory: skillDir, rawContent: raw);

      final List<ValidationError> errors = await rule.validate(context);
      expect(errors.length, equals(1));
      expect(errors.first.ruleId, equals('check-relative-paths'));
      expect(errors.first.region?.startLine, equals(7));
    });

    group('percent-encoded links', () {
      Future<ValidationResult> validateLink(String link, {String? existingFile}) async {
        final Directory skillDir = await createDummySkill(
          tempDir,
          name: 'test-skill',
          skillContent: '${buildFrontmatter(name: 'test-skill')}[doc]($link)\n',
        );
        if (existingFile != null) {
          final file = File(p.join(skillDir.path, existingFile));
          await file.parent.create(recursive: true);
          await file.writeAsString('doc');
        }
        final validator = Validator(
          ruleConfigs: {
            RelativePathsRule.ruleName: const RuleConfig(severity: AnalysisSeverity.error),
          },
        );
        return validator.validate(skillDir);
      }

      test('finds a file whose name has an encoded space', () async {
        final ValidationResult result = await validateLink(
          'my%20file.md',
          existingFile: 'my file.md',
        );
        expect(result.errors, isEmpty);
      });

      test('finds a file whose name has encoded unicode', () async {
        final ValidationResult result = await validateLink('caf%C3%A9.md', existingFile: 'café.md');
        expect(result.errors, isEmpty);
      });

      test('finds a file whose name has an encoded #', () async {
        final ValidationResult result = await validateLink('a%23b.md', existingFile: 'a#b.md');
        expect(result.errors, isEmpty);
      });

      test('finds a nested file for an encoded slash', () async {
        final ValidationResult result = await validateLink(
          'a%2Fb.md',
          existingFile: p.join('a', 'b.md'),
        );
        expect(result.errors, isEmpty);
      });

      test('resolves a link with a malformed escape as written', () async {
        final ValidationResult result = await validateLink('bad%zz.md', existingFile: 'bad%zz.md');
        expect(result.errors, isEmpty);
      });

      test('reports a link whose escape is not valid UTF-8 as missing', () async {
        final ValidationResult result = await validateLink('x%E9.md');
        expect(result.errors, [contains('Linked file does not exist: x%E9.md')]);
      });

      test('reports a link that decodes to an absolute path as missing', () async {
        final String target = p.join(tempDir.path, 'outside.md');
        await File(target).writeAsString('doc');

        final ValidationResult result = await validateLink(Uri.encodeComponent(target));

        expect(result.errors, [contains('Linked file does not exist')]);
      });

      test('reports a link with an encoded NUL as missing', () async {
        final ValidationResult result = await validateLink('a.md%00b', existingFile: 'a.md');
        expect(result.errors, [contains('Linked file does not exist: a.md%00b')]);
      });
    });
  });

  _defineWithinSkillTests();

  defineCliTests();
}

/// Defines the tests of [RelativePathsRule.withinSkill] that do not start
/// the CLI.
void _defineWithinSkillTests() {
  group(_param, () {
    late Directory tempDir;
    late Directory skillDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('within_skill_test.');
      skillDir = await _createPackage(tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    final String frontmatter = buildFrontmatter(name: 'my-skill');
    // The 1-based line of the link: the line after the frontmatter.
    final int linkLine = '\n'.allMatches(frontmatter).length + 1;

    /// Runs [RelativePathsRule] on a SKILL.md whose body is the single [link].
    Future<List<ValidationError>> lint(String link, {required bool withinSkill}) {
      final content = '${frontmatter}See [the doc]($link).\n';
      final rule = RelativePathsRule(severity: AnalysisSeverity.error, withinSkill: withinSkill);
      return rule.validate(SkillContext(directory: skillDir, rawContent: content));
    }

    // Each case: the link, the within-skill value, and the start of the
    // single expected message, or null for no message. An outside message
    // ends with its fix, so it carries no "Did you mean" suggestion.
    for (final (String link, bool withinSkill, String? reported) in [
      ('../README.md', true, _outside),
      ('../../RULES.md', true, _outside),
      ('../other-skill/SKILL.md', true, _outside), // A sibling may not be installed.
      ('references/../../README.md', true, _outside),
      ('%2E%2E%2F%2E%2E%2FRULES.md', true, _outside), // Decodes to ../../RULES.md.
      ('..%2FREADME.md', true, _outside),
      ('../../RULES.md#rules', true, _outside),
      ('../README.md "Title"', true, _outside),
      ('../MISSING.md', true, _outside), // Not also reported as missing.
      ('../READM.md', true, _outside), // No suggestion of ../README.md.
      ('references/DETAILS.md', true, null),
      ('./references/DETAILS.md', true, null),
      ('../my-skill/references/DETAILS.md', true, null), // Leaves and comes back.
      ('.', true, _missing), // A link to a directory is reported as missing.
      ('references/', true, _missing),
      ('../README.md', false, null),
      ('../../RULES.md', false, null),
      ('../other-skill/SKILL.md', false, null),
      ('../MISSING.md', false, _missing),
    ]) {
      final String target = link.split(' ').first;
      final String outcome = switch (reported) {
        null => 'allows $link',
        _outside => 'reports $link as outside the skill',
        _ => 'reports $link as missing',
      };
      test('when $withinSkill, $outcome', () async {
        final List<ValidationError> errors = await lint(link, withinSkill: withinSkill);

        expect(errors.map((ValidationError e) => e.message), [
          if (reported == _outside)
            allOf(
              startsWith('$_outside: $target (resolved to '),
              endsWith('into the skill directory.'),
            )
          else if (reported != null)
            startsWith('$reported: $target (resolved to '),
        ]);
      });
    }

    test('reports an outside link with the rule, severity, file and line', () async {
      final ValidationError error = (await lint('../README.md', withinSkill: true)).single;

      expect(error.ruleId, RelativePathsRule.ruleName);
      expect(error.severity, AnalysisSeverity.error);
      expect(error.file, 'SKILL.md');
      expect(error.region?.startLine, linkLine);
      expect(error.markdownMessage, contains('Link to an absolute URL'));
    });

    test('is false by default', () {
      expect(RelativePathsRule().withinSkill, isFalse);
      final SkillRule? rule = RuleRegistry.createRule(
        RelativePathsRule.ruleName,
        AnalysisSeverity.error,
      );
      expect(rule, isA<RelativePathsRule>().having((r) => r.withinSkill, 'withinSkill', isFalse));
    });

    for (final value in [true, false]) {
      test('RuleRegistry.createRule passes $_param: $value to the rule', () {
        final SkillRule? rule = RuleRegistry.createRule(
          RelativePathsRule.ruleName,
          AnalysisSeverity.warning,
          CustomRuleParameters({_param: value}),
        );

        expect(
          rule,
          isA<RelativePathsRule>()
              .having((r) => r.withinSkill, 'withinSkill', value)
              .having((r) => r.severity, 'severity', AnalysisSeverity.warning),
        );
      });
    }

    test('$_flag=true sets the parameter', () {
      final parser = ArgParser()
        ..addFlag(RelativePathsRule.ruleName)
        ..addOption(_flag.substring(2));

      final Map<String, RuleConfigPatch> configs = resolveRuleConfigsFromCli(
        parser.parse(['$_flag=true']),
      );

      expect(configs[RelativePathsRule.ruleName]?.parameters?[_param], isTrue);
    });

    group('in skills_lint.yaml', () {
      Configuration parseRule(String ruleYaml) {
        return ConfigParser.parse('''
skills_lint:
  rules:
    ${RelativePathsRule.ruleName}:
$ruleYaml
''');
      }

      test('accepts a boolean', () {
        final Configuration config = parseRule('      severity: error\n      $_param: true');

        expect(config.parsingErrors, isEmpty);
        final RuleConfigPatch? patch = config.ruleConfigs[RelativePathsRule.ruleName];
        expect(patch?.severity, AnalysisSeverity.error);
        expect(patch?.parameters?[_param], isTrue);
      });

      test('reports a type error for a quoted "true"', () {
        final Configuration config = parseRule('      $_param: "true"');

        expect(config.parsingErrors, [contains('Expected bool')]);
      });
    });

    test(
      'flags the relative link that check-absolute-paths --fix writes outside the skill',
      () async {
        // The check-absolute-paths fixer rewrites an absolute link to an
        // existing file as a path relative to the skill. For a file outside the
        // skill that path starts with ../, which within-skill then reports.
        final String outsideFile = p.join(tempDir.path, 'RULES.md');
        final content = '${frontmatter}See [rules]($outsideFile).\n';

        final String fixed = await AbsolutePathsRule().fix(
          SkillContext(directory: skillDir, rawContent: content),
        );

        expect(fixed, contains('[rules](../../RULES.md)'));
        final rule = RelativePathsRule(severity: AnalysisSeverity.error, withinSkill: true);
        final List<ValidationError> errors = await rule.validate(
          SkillContext(directory: skillDir, rawContent: fixed),
        );
        expect(errors.single.message, startsWith('$_outside: ../../RULES.md'));
      },
    );
  });
}

/// Defines the tests that start the CLI. [main] calls this, and
/// `compiled_test/cli_test.dart` calls it again to run the same tests
/// against the compiled binary.
void defineCliTests() {
  group('CLI $_flag', () {
    late Directory tempDir;
    late String skillsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('within_skill_cli_test.');
      final Directory skillDir = await _createPackage(
        tempDir,
        mySkillBody: 'See [rules](../../RULES.md) and [details](references/DETAILS.md).\n',
      );
      skillsPath = p.dirname(skillDir.path);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<TestProcess> run(List<String> args) {
      return startCli(['-d', skillsPath, '--check-relative-paths', ...args]);
    }

    Future<void> writeConfig(String contents) {
      return File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString(contents);
    }

    Future<void> writeRuleConfig(String rule) {
      return writeConfig('''
skills_lint:
  rules:
    ${RelativePathsRule.ruleName}:
$rule
''');
    }

    test('--help lists the flag', () async {
      final TestProcess process = await startCli(['--help']);

      await process.shouldExit(0);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      expect(stdout, contains(_flag));
    });

    test('passes an outside link without the flag', () async {
      final TestProcess process = await run([]);
      await process.shouldExit(0);
    });

    test('reports an outside link with $_flag=true', () async {
      final TestProcess process = await run(['$_flag=true']);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('$_outside: ../../RULES.md'));
      expect(stderr, isNot(contains('references/DETAILS.md')));
    });

    test('reads $_param from skills_lint.yaml', () async {
      await writeRuleConfig('      severity: error\n      $_param: true');

      final TestProcess process = await startCli([
        '-d',
        skillsPath,
      ], workingDirectory: tempDir.path);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('$_outside: ../../RULES.md'));
    });

    test('$_flag=false overrides skills_lint.yaml', () async {
      await writeRuleConfig('      severity: error\n      $_param: true');

      final TestProcess process = await startCli([
        '-d',
        skillsPath,
        '$_flag=false',
      ], workingDirectory: tempDir.path);

      await process.shouldExit(0);
    });

    test('applies $_param to published skills only, in one run', () async {
      // Contributor skills in .agents/skills link outside their directory
      // too, and the file exists, so they pass without within-skill.
      final Directory contributorSkill = await Directory(
        p.join(tempDir.path, '.agents', 'skills', 'contributor-skill'),
      ).create(recursive: true);
      await File(p.join(contributorSkill.path, 'SKILL.md')).writeAsString(
        '${buildFrontmatter(name: 'contributor-skill')}See [rules](../../../RULES.md).\n',
      );
      await writeConfig('''
skills_lint:
  rules:
    ${RelativePathsRule.ruleName}: error
  directories:
    - path: skills
      rules:
        ${RelativePathsRule.ruleName}:
          severity: error
          $_param: true
    - path: .agents/skills
''');

      final TestProcess process = await startCli([], workingDirectory: tempDir.path);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('$_outside: ../../RULES.md'));
      expect(stderr, isNot(contains('../../../RULES.md')));
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      expect(stdout, contains('--- Validating skill: contributor-skill ---'));
    });

    test('reports the outside link in --format=json', () async {
      final TestProcess process = await run(['$_flag=true', '--format=json']);

      await process.shouldExit(1);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      expect(stdout, contains(_outside));
      expect(stdout, contains('"${RelativePathsRule.ruleName}"'));
    });

    test('reports the outside link in --format=sarif', () async {
      final TestProcess process = await run(['$_flag=true', '--format=sarif']);

      await process.shouldExit(1);
      final String stdout = (await process.stdout.rest.toList()).join('\n');
      final Object? sarif = jsonDecode(stdout);
      expect(sarif, isA<Map<String, Object?>>());
      expect(stdout, contains(_outside));
      expect(stdout, contains('"ruleId": "${RelativePathsRule.ruleName}"'));
    });

    test('--generate-baseline records the outside link so the next run passes', () async {
      final String baseline = p.join(tempDir.path, 'baseline.json');

      final TestProcess generate = await run([
        '$_flag=true',
        '--generate-baseline',
        '--ignore-file=$baseline',
      ]);
      await generate.shouldExit(0);

      final TestProcess rerun = await run(['$_flag=true', '--ignore-file=$baseline']);
      await rerun.shouldExit(0);
    });
  });
}
