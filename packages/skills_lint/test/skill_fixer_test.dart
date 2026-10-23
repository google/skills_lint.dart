// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests of [SkillFixer], the loop behind `--fix` that keeps a fix only when
/// it lowers a skill's errors, then warnings.
///
/// Each scenario also runs `--fix` for real and checks that the disk ends up
/// as the fixer predicted, because `--fix --dry-run` prints that prediction.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/entry_point.dart';
import 'package:skills_lint/src/fixable_rule.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/fix_outcome.dart';
import 'package:skills_lint/src/models/ignore_entry.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/models/skills_ignores.dart';
import 'package:skills_lint/src/models/skipped_fix.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/absolute_paths_rule.dart';
import 'package:skills_lint/src/rules/name_format_rule.dart';
import 'package:skills_lint/src/rules/published_skill_name_rule.dart';
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:skills_lint/src/rules/trailing_whitespace_rule.dart';
import 'package:skills_lint/src/skill_fixer.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A rule with one error per missing `x` up to [target], whose fix adds a
/// single `x`, so each fix pass can keep only one fix.
class _OneStepAtATimeRule extends SkillRule implements FixableRule {
  _OneStepAtATimeRule(this.target);

  final int target;

  @override
  String get name => 'one-step-at-a-time';

  @override
  AnalysisSeverity get severity => AnalysisSeverity.error;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final int missing = target - 'x'.allMatches(context.rawContent).length;
    return [
      for (var i = 0; i < missing; i++)
        ValidationError(ruleId: name, message: 'Missing x', severity: severity, file: 'SKILL.md'),
    ];
  }

  @override
  Future<String> fix(SkillContext context) async => '${context.rawContent}x';
}

void main() {
  late Directory root;

  setUp(() async {
    root = Directory(
      (await Directory.systemTemp.createTemp('skill_fixer_test.')).resolveSymbolicLinksSync(),
    );
    addTearDown(() => root.delete(recursive: true));
  });

  const Map<String, RuleConfig> publishedName = {
    PublishedSkillNameRule.ruleName: RuleConfig(severity: AnalysisSeverity.error),
  };

  /// Writes a package named `bar` with a skill named [name] in `skills/`.
  Future<Directory> createPackageSkill(String name, {String body = 'Body\n'}) async {
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString('name: bar\n');
    return createDummySkill(
      Directory(p.join(root.path, 'skills')),
      name: name,
      skillContent: '${buildFrontmatter(name: name)}$body',
    );
  }

  /// Runs [SkillFixer] on [skillDir] in memory.
  Future<FixOutcome> predict(
    Directory skillDir,
    Map<String, RuleConfig> ruleConfigs, {
    List<SkillRule> customRules = const [],
  }) async {
    final validator = Validator(ruleConfigs: ruleConfigs, customRules: customRules);
    return SkillFixer(
      validator: validator,
      applyIgnores: (_) {},
      onFixFailed: (ruleName, error) => fail('$ruleName fix threw $error'),
    ).fix(await validator.validate(skillDir));
  }

  /// Runs `--fix` on [skillDir].
  Future<void> applyFix(Directory skillDir, Map<String, RuleConfig> ruleConfigs) =>
      validateSkillsInternal(
        individualSkillPaths: [skillDir.path],
        fixApply: true,
        quiet: true,
        resolvedRuleConfigs: {
          for (final MapEntry(:key, :value) in ruleConfigs.entries)
            key: RuleConfigPatch(severity: value.severity, parameters: value.parameters),
        },
      );

  /// The rule and severity of each diagnostic, which unlike messages don't
  /// hold the path of the skill.
  List<String> diagnostics(ValidationResult result) => [
    for (final ValidationError error in result.validationErrors)
      if (!error.isIgnored) '${error.ruleId} ${error.severity.name}',
  ];

  /// Checks that `--fix` leaves on disk what [predicted] says.
  Future<void> expectDiskMatches(
    FixOutcome predicted,
    Directory skillDir,
    Map<String, RuleConfig> ruleConfigs,
  ) async {
    await applyFix(skillDir, ruleConfigs);
    final fixedDir = Directory(p.join(skillDir.parent.path, predicted.directoryName));
    expect(fixedDir.existsSync(), isTrue);
    expect(File(p.join(fixedDir.path, 'SKILL.md')).readAsStringSync(), predicted.content);
    final ValidationResult onDisk = await Validator(ruleConfigs: ruleConfigs).validate(fixedDir);
    expect(diagnostics(onDisk), diagnostics(predicted.result));
  }

  test('keeps fixes that need the planned directory name', () async {
    const Map<String, RuleConfig> ruleConfigs = {
      ...publishedName,
      TrailingWhitespaceRule.ruleName: RuleConfig(severity: AnalysisSeverity.error),
    };
    final Directory skillDir = await createPackageSkill('foo', body: 'Body   \n');

    final FixOutcome outcome = await predict(skillDir, ruleConfigs);

    expect(outcome.directoryName, 'bar-foo');
    expect(outcome.appliedRuleNames, [
      PublishedSkillNameRule.ruleName,
      TrailingWhitespaceRule.ruleName,
    ]);
    expect(outcome.result.isValid, isTrue);
    expect(outcome.settled, isTrue);
    await expectDiskMatches(outcome, skillDir, ruleConfigs);
  });

  test('drops a fix that would turn a warning into an error', () async {
    final String guidePath = p.join(root.path, 'shared', 'guide.md');
    await File(guidePath).create(recursive: true);
    final Map<String, RuleConfig> ruleConfigs = {
      RelativePathsRule.ruleName: RuleConfig(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {RelativePathsRule.withinSkillParameter: true}),
      ),
    };
    final Directory skillDir = await createPackageSkill('bar-foo', body: '[guide]($guidePath)\n');
    final String original = File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync();

    final FixOutcome outcome = await predict(skillDir, ruleConfigs);

    expect(outcome.content, original);
    final SkippedFix skipped = outcome.skippedFixes.single;
    expect(skipped.ruleName, AbsolutePathsRule.ruleName);
    expect(skipped.grownRuleNames, [RelativePathsRule.ruleName]);
    expect(outcome.result.isValid, isTrue);
    await expectDiskMatches(outcome, skillDir, ruleConfigs);
  });

  test('drops a rename onto an existing directory, so `name` stays put across runs', () async {
    // Renaming `foo` to `bar-foo` collides with the existing skill. Without the
    // guard, `name` flipped between `foo` and `bar-foo` on every run.
    await createPackageSkill('bar-foo');
    final Directory skillDir = await createPackageSkill('foo');
    final String original = File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync();

    final FixOutcome outcome = await predict(skillDir, publishedName);

    expect(outcome.content, original);
    expect(outcome.skippedFixes.single.ruleName, PublishedSkillNameRule.ruleName);
    expect(outcome.skippedFixes.single.blockedDirectoryName, 'bar-foo');
    expect(outcome.skippedFixes.single.grownRuleNames, [NameFormatRule.ruleName]);
    for (var run = 1; run <= 2; run++) {
      await applyFix(skillDir, publishedName);
      expect(
        File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync(),
        original,
        reason: 'run $run',
      );
    }
  });

  test('renames a directory whose name differs only in case', () async {
    // On a case-insensitive file system, `bar-x` already "exists" as `Bar-x`.
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString('name: bar\n');
    final Directory skillDir = await createDummySkill(
      Directory(p.join(root.path, 'skills')),
      name: 'Bar-x',
      skillContent: '${buildFrontmatter(name: 'x')}Body\n',
    );

    final FixOutcome outcome = await predict(skillDir, publishedName);

    expect(outcome.skippedFixes, isEmpty);
    expect(outcome.directoryName, 'bar-x');
    await applyFix(skillDir, publishedName);
    expect(Directory(p.join(root.path, 'skills')).listSync().map((e) => p.basename(e.path)), [
      'bar-x',
    ]);
  });

  test('stops after maxPasses and says the fixes did not settle', () async {
    final Directory skillDir = await createPackageSkill('bar-foo');
    final FixOutcome outcome = await predict(
      skillDir,
      const {},
      customRules: [_OneStepAtATimeRule(SkillFixer.maxPasses + 1)],
    );

    expect(outcome.settled, isFalse);
    expect('x'.allMatches(outcome.content), hasLength(SkillFixer.maxPasses));
  });

  test('re-validates all skills after a rename breaks a sibling skill link', () async {
    // `aaa` links to `../foo/SKILL.md`. Both get renamed (`bar-aaa` and
    // `bar-foo`), which breaks `bar-aaa`'s link after `aaa` already passed.
    await createPackageSkill('aaa', body: 'See [foo](../foo/SKILL.md).\n');
    await createPackageSkill('foo');
    final err = CapturedOutput();

    final bool success = await IOOverrides.runZoned(
      () => validateSkillsInternal(
        skillDirPaths: [p.join(root.path, 'skills')],
        fixApply: true,
        quiet: true,
        resolvedRuleConfigs: const {
          PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      ),
      stdout: CapturedOutput.new,
      stderr: () => err,
    );

    expect(success, isFalse);
    expect(err.buffer.toString(), contains('Linked file does not exist: ../foo/SKILL.md'));
  });

  test('passes when a sibling rename fixes a skill link', () async {
    // `aaa` links to `../bar-zzz/SKILL.md`, which exists only after `--fix`
    // renames `zzz` to `bar-zzz`, after `aaa` already failed.
    await createPackageSkill('aaa', body: 'See [zzz](../bar-zzz/SKILL.md).\n');
    await createPackageSkill('zzz');

    final bool success = await IOOverrides.runZoned(
      () => validateSkillsInternal(
        skillDirPaths: [p.join(root.path, 'skills')],
        fixApply: true,
        quiet: true,
        resolvedRuleConfigs: const {
          PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      ),
      stdout: CapturedOutput.new,
      stderr: CapturedOutput.new,
    );

    expect(Directory(p.join(root.path, 'skills', 'bar-zzz')).existsSync(), isTrue);
    expect(success, isTrue);
  });

  test('moves baseline ignore entries to the new skill name when a fix renames a skill', () async {
    await createPackageSkill('foo', body: 'See [missing](missing.md).\n');
    final ignoreFile = File(p.join(root.path, 'skills', defaultIgnoreFileName));
    await ignoreFile.writeAsString(
      jsonEncode({
        SkillsIgnores.skillsKey: {
          'foo': [
            {
              IgnoreEntry.ruleIdKey: RelativePathsRule.ruleName,
              IgnoreEntry.fileNameKey: 'SKILL.md',
            },
          ],
        },
      }),
    );

    final bool firstRun = await validateSkillsInternal(
      skillDirPaths: [p.join(root.path, 'skills')],
      fixApply: true,
      quiet: true,
      resolvedRuleConfigs: const {
        PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
      },
    );
    expect(firstRun, isTrue);

    final saved = jsonDecode(ignoreFile.readAsStringSync()) as Map<String, dynamic>;
    final skills = saved[SkillsIgnores.skillsKey] as Map<String, dynamic>;
    expect(skills.keys, ['bar-foo']);

    final out = CapturedOutput();
    final bool secondRun = await IOOverrides.runZoned(
      () => validateSkillsInternal(
        skillDirPaths: [p.join(root.path, 'skills')],
        quiet: true,
        resolvedRuleConfigs: const {
          PublishedSkillNameRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
          RelativePathsRule.ruleName: RuleConfigPatch(severity: AnalysisSeverity.error),
        },
      ),
      stdout: () => out,
      stderr: CapturedOutput.new,
    );
    expect(secondRun, isTrue);
    expect(out.buffer.toString(), isNot(contains('Stale ignore entry')));
  });
}
