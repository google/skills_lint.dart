// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests of [SkillFixer], the loop behind `--fix` that keeps a fix only when
/// it lowers a skill's errors, then warnings.
///
/// Each scenario also runs `--fix` for real and checks that the disk ends up
/// as the fixer predicted, because `--fix --dry-run` prints that prediction.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/entry_point.dart';
import 'package:skills_lint/src/fixable_rule.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/fix_outcome.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/models/skipped_fix.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rules/absolute_paths_rule.dart';
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

/// A rule that always reports an error and whose fix always throws.
class _ThrowingFixRule extends SkillRule implements FixableRule {
  static const String ruleName = 'throwing-fix';

  @override
  String get name => ruleName;

  @override
  AnalysisSeverity get severity => AnalysisSeverity.error;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async => [
    ValidationError(ruleId: name, message: 'Always', severity: severity, file: 'SKILL.md'),
  ];

  @override
  Future<String> fix(SkillContext context) => throw StateError('broken fixer');
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
    bool canRename = true,
  }) async {
    final validator = Validator(ruleConfigs: ruleConfigs, customRules: customRules);
    return SkillFixer(
      validator: validator,
      applyIgnores: (_) {},
      onFixFailed: (ruleName, error) => fail('$ruleName fix threw $error'),
    ).fix(await validator.validate(skillDir), canRename: canRename);
  }

  /// Runs `--fix` on [skillDir], and returns whether the run passed and what
  /// it wrote to stderr.
  Future<({bool passed, String err})> runFix(
    Directory skillDir,
    Map<String, RuleConfig> ruleConfigs, {
    List<SkillRule> customRules = const [],
  }) async {
    final err = CapturedOutput();
    final bool passed = await IOOverrides.runZoned(
      () => validateSkillsInternal(
        individualSkillPaths: [skillDir.path],
        fixApply: true,
        quiet: true,
        customRules: customRules,
        resolvedRuleConfigs: {
          for (final MapEntry(:key, :value) in ruleConfigs.entries)
            key: RuleConfigPatch(severity: value.severity, parameters: value.parameters),
        },
      ),
      stderr: () => err,
    );
    return (passed: passed, err: err.buffer.toString());
  }

  /// Runs `--fix` on [skillDir], and returns what it wrote to stderr.
  Future<String> applyFix(Directory skillDir, Map<String, RuleConfig> ruleConfigs) async =>
      (await runFix(skillDir, ruleConfigs)).err;

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

    final FixOutcome outcome = await predict(skillDir, publishedName, canRename: false);

    expect(outcome.content, original);
    expect(outcome.skippedFixes.single.ruleName, PublishedSkillNameRule.ruleName);
    expect(outcome.skippedFixes.single.needsRename, isTrue);
    for (var run = 1; run <= 2; run++) {
      final String err = await applyFix(skillDir, publishedName);
      expect(
        File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync(),
        original,
        reason: 'run $run',
      );
      expect(err, contains('bar-foo'), reason: 'run $run');
    }
  });

  test('drops a fix that needs a blocked rename even when it clears other errors', () async {
    // `name: Foo` breaks invalid-skill-name and published-skill-name. The
    // fix to `bar-foo` clears both, but under the current directory name it
    // leaves `name` and the directory different, and a sibling has the name.
    await createPackageSkill('bar-foo');
    final Directory skillDir = await createDummySkill(
      Directory(p.join(root.path, 'skills')),
      name: 'Foo',
      skillContent: '${buildFrontmatter(name: 'Foo')}Body\n',
    );
    final String original = File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync();

    final FixOutcome outcome = await predict(skillDir, publishedName, canRename: false);

    expect(outcome.content, original);
    expect(outcome.skippedFixes, isNotEmpty);
    expect(outcome.skippedFixes.map((s) => s.needsRename), everyElement(isTrue));
    final String err = await applyFix(skillDir, publishedName);
    expect(File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync(), original);
    expect(err, contains('bar-foo'));
  });

  test('fails the run when the fixed SKILL.md cannot be written', () async {
    const Map<String, RuleConfig> warnOnWhitespace = {
      TrailingWhitespaceRule.ruleName: RuleConfig(severity: AnalysisSeverity.warning),
    };
    final Directory skillDir = await createPackageSkill('bar-foo', body: 'Body   \n');
    final String skillMd = p.join(skillDir.path, 'SKILL.md');
    await Process.run('chmod', ['444', skillMd]);
    addTearDown(() => Process.run('chmod', ['644', skillMd]));

    final ({bool passed, String err}) run = await runFix(skillDir, warnOnWhitespace);

    expect(run.passed, isFalse, reason: run.err);
    expect(run.err, contains('bar-foo'));
    expect(File(skillMd).readAsStringSync(), contains('Body   \n'));
  }, skip: Platform.isWindows ? 'uses the POSIX chmod command' : null);

  test('still writes the other fixes when the rename fails at write time', () async {
    const Map<String, RuleConfig> ruleConfigs = {
      ...publishedName,
      TrailingWhitespaceRule.ruleName: RuleConfig(severity: AnalysisSeverity.error),
    };
    final Directory skillDir = await createPackageSkill('foo', body: 'Body   \n');
    // A read-only parent passes the preflight check and fails the rename.
    await Process.run('chmod', ['555', skillDir.parent.path]);
    addTearDown(() => Process.run('chmod', ['755', skillDir.parent.path]));

    final String err = await applyFix(skillDir, ruleConfigs);

    expect(skillDir.existsSync(), isTrue);
    final String content = File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync();
    expect(content, contains('Body\n'));
    expect(content, contains('name: foo'));
    expect(err, contains('bar-foo'));
  }, skip: Platform.isWindows ? 'uses the POSIX chmod command' : null);

  test('reports a fixer that throws once per skill, across passes and a re-plan', () async {
    // The sibling blocks the planned rename, so the session plans twice.
    await createPackageSkill('bar-foo');
    final Directory skillDir = await createPackageSkill('foo');

    final ({bool passed, String err}) run = await runFix(
      skillDir,
      publishedName,
      customRules: [_ThrowingFixRule()],
    );

    expect("'${_ThrowingFixRule.ruleName}' fix".allMatches(run.err), hasLength(1), reason: run.err);
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
}
