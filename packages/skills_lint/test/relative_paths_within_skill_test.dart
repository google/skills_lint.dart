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
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

const String _param = RelativePathsRule.withinSkillParameter;
const String _flag = '--${RelativePathsRule.ruleName}-$_param';
const String _outside = 'Linked file is outside the skill directory';

/// Creates a package with two published skills and a file next to them:
///
/// ```text
/// <root>/
///   RULES.md
///   skills/
///     README.md
///     my-skill/
///       SKILL.md        (written by each test)
///       references/DETAILS.md
///     other-skill/
///       SKILL.md
/// ```
///
/// Returns the `my-skill` directory. Every linked file exists, so a
/// diagnostic about an outside link is never caused by a missing file.
Future<Directory> _createPackage(Directory root) async {
  final Directory skills = await Directory(p.join(root.path, 'skills')).create();
  final Directory mySkill = await Directory(p.join(skills.path, 'my-skill')).create();
  await Directory(p.join(mySkill.path, 'references')).create();
  await File(p.join(mySkill.path, 'references', 'DETAILS.md')).writeAsString('Details');
  final Directory otherSkill = await Directory(p.join(skills.path, 'other-skill')).create();
  await File(
    p.join(otherSkill.path, 'SKILL.md'),
  ).writeAsString('${buildFrontmatter(name: 'other-skill')}Body\n');
  await File(p.join(skills.path, 'README.md')).writeAsString('Readme');
  await File(p.join(root.path, 'RULES.md')).writeAsString('Rules');
  return mySkill;
}

void main() {
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

  group('$_param: true', () {
    for (final (:String link, :String why) in [
      (link: '../README.md', why: 'one ../ leaves the skill'),
      (link: '../../RULES.md', why: 'a nested ../../ leaves the skill'),
      (link: '../other-skill/SKILL.md', why: 'a sibling skill may not be installed'),
      (link: 'references/../../README.md', why: 'a ../ after a subdirectory leaves the skill'),
      (link: '%2E%2E%2F%2E%2E%2FRULES.md', why: 'percent escapes decode to ../../'),
      (link: '..%2FREADME.md', why: 'an encoded slash decodes to ../'),
      (link: '../../RULES.md#rules', why: 'a fragment does not hide the path'),
      (link: '../README.md "Title"', why: 'a title does not hide the path'),
    ]) {
      test('reports $link because $why', () async {
        final List<ValidationError> errors = await lint(link, withinSkill: true);

        final ValidationError error = errors.single;
        expect(error.ruleId, RelativePathsRule.ruleName);
        expect(error.severity, AnalysisSeverity.error);
        expect(error.file, 'SKILL.md');
        expect(error.region?.startLine, linkLine);
        expect(error.message, startsWith('$_outside: ${link.split(' ').first} (resolved to '));
        expect(error.message, endsWith('or copy the content into the skill directory.'));
        expect(error.markdownMessage, contains('Link to an absolute URL'));
      });
    }

    test('reports an outside link whose file is missing twice, once for each problem', () async {
      final List<ValidationError> errors = await lint('../MISSING.md', withinSkill: true);

      expect(errors.map((ValidationError e) => e.message), [
        startsWith('$_outside: ../MISSING.md'),
        startsWith('Linked file does not exist: ../MISSING.md'),
      ]);
    });

    for (final (:String link, :String why) in [
      (link: 'references/DETAILS.md', why: 'it stays in the skill'),
      (link: './references/DETAILS.md', why: 'it stays in the skill'),
      (link: '../my-skill/references/DETAILS.md', why: 'it leaves and comes back into the skill'),
      (link: 'https://example.com/RULES.md', why: 'it is an absolute URL'),
      (link: '#usage', why: 'it is an anchor'),
      (link: 'mailto:someone@example.com', why: 'it has a scheme'),
    ]) {
      test('allows $link because $why', () async {
        expect(await lint(link, withinSkill: true), isEmpty);
      });
    }

    // The rule reports a link to a directory as a missing file, so only
    // check that these links are not reported as outside the skill.
    for (final link in ['.', 'references/']) {
      test('does not report $link as outside the skill', () async {
        final List<ValidationError> errors = await lint(link, withinSkill: true);

        expect(
          errors.map((ValidationError e) => e.message),
          everyElement(isNot(startsWith(_outside))),
        );
      });
    }
  });

  group('$_param: false', () {
    for (final link in ['../README.md', '../../RULES.md', '../other-skill/SKILL.md']) {
      test('allows $link because the file exists', () async {
        expect(await lint(link, withinSkill: false), isEmpty);
      });
    }

    test('is the default', () {
      expect(RelativePathsRule().withinSkill, isFalse);
      final SkillRule? rule = RuleRegistry.createRule(
        RelativePathsRule.ruleName,
        AnalysisSeverity.error,
      );
      expect(rule, isA<RelativePathsRule>().having((r) => r.withinSkill, 'withinSkill', isFalse));
    });
  });

  group('RuleRegistry.createRule for ${RelativePathsRule.ruleName}', () {
    for (final value in [true, false]) {
      test('passes $_param: $value to the rule', () {
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
  });

  group('resolveRuleConfigsFromCli $_flag', () {
    Map<String, RuleConfigPatch> resolve(List<String> args) {
      final parser = ArgParser()
        ..addFlag(RelativePathsRule.ruleName)
        ..addOption(_flag.substring(2));
      return resolveRuleConfigsFromCli(parser.parse(args));
    }

    for (final (:String raw, :bool parsed) in [
      (raw: 'true', parsed: true),
      (raw: 'TRUE', parsed: true),
      (raw: 'false', parsed: false),
    ]) {
      test('reads $raw as $parsed', () {
        final Map<String, RuleConfigPatch> configs = resolve(['$_flag=$raw']);

        expect(configs[RelativePathsRule.ruleName]?.parameters?[_param], parsed);
      });
    }

    test('rejects a value that is not true or false', () {
      expect(
        () => resolve(['$_flag=yes']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invalid value "yes" for parameter "${_flag.substring(2)}". '
                'Expected "true" or "false".',
          ),
        ),
      );
    });
  });

  group('skills_lint.yaml $_param parameter', () {
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

    for (final invalid in ['"true"', '1', 'on-ish']) {
      test('reports a type error for $_param: $invalid', () {
        final Configuration config = parseRule('      $_param: $invalid');

        expect(config.parsingErrors, [contains('Expected bool')]);
      });
    }
  });

  defineCliTests();
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
      final Directory skillDir = await _createPackage(tempDir);
      skillsPath = p.dirname(skillDir.path);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString(
        '${buildFrontmatter(name: 'my-skill')}'
        'See [rules](../../RULES.md) and [details](references/DETAILS.md).\n',
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<TestProcess> run(List<String> args) {
      return startCli(['-d', skillsPath, '--check-relative-paths', ...args]);
    }

    Future<void> writeConfig(String rule) {
      return File(p.join(tempDir.path, 'skills_lint.yaml')).writeAsString('''
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
      await writeConfig('      severity: error\n      $_param: true');

      final TestProcess process = await startCli([
        '-d',
        skillsPath,
      ], workingDirectory: tempDir.path);

      await process.shouldExit(1);
      final String stderr = (await process.stderr.rest.toList()).join('\n');
      expect(stderr, contains('$_outside: ../../RULES.md'));
    });

    test('$_flag=false overrides skills_lint.yaml', () async {
      await writeConfig('      severity: error\n      $_param: true');

      final TestProcess process = await startCli([
        '-d',
        skillsPath,
        '$_flag=false',
      ], workingDirectory: tempDir.path);

      await process.shouldExit(0);
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
