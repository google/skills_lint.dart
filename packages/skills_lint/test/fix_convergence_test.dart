// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Property tests across every built-in [FixableRule] in [RuleRegistry].
///
/// A new built-in fixable rule registered in [RuleRegistry.allChecks] is
/// automatically checked for idempotence, progress on its own diagnostics,
/// convergence, and dry-run/apply equivalence.
library;

import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/entry_point.dart';
import 'package:skills_lint/src/fixable_rule.dart';
import 'package:skills_lint/src/models/analysis_severity.dart';
import 'package:skills_lint/src/models/check_type.dart';
import 'package:skills_lint/src/models/custom_rule_parameters.dart';
import 'package:skills_lint/src/models/fix_outcome.dart';
import 'package:skills_lint/src/models/rule_config.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/models/skill_rule.dart';
import 'package:skills_lint/src/models/validation_error.dart';
import 'package:skills_lint/src/rule_registry.dart';
import 'package:skills_lint/src/rules/published_skill_name_rule.dart';
import 'package:skills_lint/src/rules/relative_paths_rule.dart';
import 'package:skills_lint/src/skill_fixer.dart';
import 'package:skills_lint/src/validator.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A named rule configuration in the convergence matrix.
typedef _NamedConfig = ({String label, Map<String, RuleConfig> ruleConfigs});

/// A skill fixture that can be materialized into a fresh temporary directory.
typedef _CorpusFixture = ({
  String label,
  String dirName,
  String Function(String rootPath) buildContent,
});

final List<SkillRule> _fixableRules = [
  for (final CheckType check in RuleRegistry.allChecks)
    if (RuleRegistry.createRule(check.name, AnalysisSeverity.error) case final SkillRule rule
        when rule is FixableRule)
      rule,
];

final List<_NamedConfig> _configMatrix = [
  (
    label: 'defaults',
    ruleConfigs: {
      for (final CheckType check in RuleRegistry.allChecks)
        check.name: RuleConfig(severity: check.defaultSeverity),
    },
  ),
  (
    label: 'all-rules-on',
    ruleConfigs: {
      for (final CheckType check in RuleRegistry.allChecks)
        if (check.name != PublishedSkillNameRule.ruleName)
          check.name: const RuleConfig(severity: AnalysisSeverity.error),
    },
  ),
  (
    label: 'within-skill',
    ruleConfigs: {
      for (final CheckType check in RuleRegistry.allChecks)
        if (check.name != PublishedSkillNameRule.ruleName)
          check.name: RuleConfig(
            severity: AnalysisSeverity.error,
            parameters: check.name == RelativePathsRule.ruleName
                ? CustomRuleParameters(const {RelativePathsRule.withinSkillParameter: true})
                : null,
          ),
    },
  ),
  (
    label: 'published-skill-name',
    ruleConfigs: {
      for (final CheckType check in RuleRegistry.allChecks)
        check.name: const RuleConfig(severity: AnalysisSeverity.error),
    },
  ),
];

final List<_CorpusFixture> _corpus = _buildCorpus();

List<_CorpusFixture> _buildCorpus() {
  final fixtures = <_CorpusFixture>[];
  _addDiskFixtures(fixtures);
  final rng = Random(42);
  for (var i = 0; i < 8; i++) {
    fixtures.add(_buildMutatedFixture(rng, i));
  }
  return fixtures;
}

void _addDiskFixtures(List<_CorpusFixture> fixtures) {
  final invalidFile = File(p.join('example', 'skills', 'invalid', 'SKILL.md'));
  if (invalidFile.existsSync()) {
    final String content = invalidFile.readAsStringSync();
    fixtures.add((label: 'example/invalid', dirName: 'invalid', buildContent: (_) => content));
  }

  final sampleRoot = Directory(p.join('benchmark', 'sample_skills'));
  if (!sampleRoot.existsSync()) {
    return;
  }
  final List<Directory> sampleDirs = sampleRoot.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in sampleDirs) {
    final skillFile = File(p.join(dir.path, 'SKILL.md'));
    if (skillFile.existsSync()) {
      final String content = skillFile.readAsStringSync();
      final String name = p.basename(dir.path);
      fixtures.add((label: 'sample/$name', dirName: name, buildContent: (_) => content));
    }
  }
}

_CorpusFixture _buildMutatedFixture(Random rng, int index) {
  const dirNames = ['my-skill', 'pkg-tool', 'bad_dir', 'foo', 'pkg-helper'];
  const fmNames = ['my-skill', 'Wrong-Name', 'foo', 'pkg-tool', '123'];
  final String dirName = dirNames[rng.nextInt(dirNames.length)];
  final String fmName = fmNames[rng.nextInt(fmNames.length)];
  final bool trailingSpaces = rng.nextBool();
  final bool carriageReturn = rng.nextBool();
  final bool insideAbsLink = rng.nextBool();
  final bool outsideAbsLink = rng.nextBool();
  return (
    label: 'mutated-$index ($dirName / $fmName)',
    dirName: dirName,
    buildContent: (String rootPath) => _renderMutatedSkill(
      rootPath: rootPath,
      index: index,
      dirName: dirName,
      fmName: fmName,
      trailingSpaces: trailingSpaces,
      carriageReturn: carriageReturn,
      insideAbsLink: insideAbsLink,
      outsideAbsLink: outsideAbsLink,
    ),
  );
}

String _renderMutatedSkill({
  required String rootPath,
  required int index,
  required String dirName,
  required String fmName,
  required bool trailingSpaces,
  required bool carriageReturn,
  required bool insideAbsLink,
  required bool outsideAbsLink,
}) {
  final buffer = StringBuffer()
    ..write(buildFrontmatter(name: fmName, description: 'Mutated skill $index.'))
    ..write('# Heading${trailingSpaces ? '   ' : ''}\n');
  if (carriageReturn) {
    buffer.write('Line before CR   \rAfter CR\n');
  }
  if (insideAbsLink) {
    final String insideTarget = p.join(rootPath, 'skills', dirName, 'local.md');
    buffer.write('See [local]($insideTarget).\n');
  }
  if (outsideAbsLink) {
    final String outsideTarget = p.join(rootPath, 'shared', 'guide.md');
    buffer.write('See [outside]($outsideTarget).\n');
  }
  return buffer.toString();
}

/// Materializes [fixture] into a fresh package workspace under [tempRoot].
Future<Directory> _materialize(Directory tempRoot, _CorpusFixture fixture) async {
  final box = Directory(
    p.join(tempRoot.path, fixture.label.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_')),
  )..createSync(recursive: true);
  final String rootPath = box.resolveSymbolicLinksSync();
  await File(p.join(rootPath, 'pubspec.yaml')).writeAsString('name: pkg\n');
  await File(p.join(rootPath, 'shared', 'guide.md')).create(recursive: true);
  final skillDir = Directory(p.join(rootPath, 'skills', fixture.dirName));
  await skillDir.create(recursive: true);
  await File(p.join(skillDir.path, 'local.md')).writeAsString('Local doc\n');
  await File(p.join(skillDir.path, 'SKILL.md')).writeAsString(fixture.buildContent(rootPath));
  return skillDir;
}

List<String> _activeDiagnostics(ValidationResult result) => [
  for (final ValidationError error in result.validationErrors)
    if (!error.isIgnored) '${error.ruleId}:${error.severity.name}',
];

Future<void> _verifyRuleProperties(SkillRule rule) async {
  final fixable = rule as FixableRule;
  final Directory tempRoot = await Directory.systemTemp.createTemp('fix_p1_p2.');
  addTearDown(() => tempRoot.delete(recursive: true));

  final validator = Validator(
    ruleConfigs: {
      for (final CheckType check in RuleRegistry.allChecks)
        check.name: RuleConfig(
          severity: check.name == rule.name ? AnalysisSeverity.error : AnalysisSeverity.disabled,
        ),
    },
  );

  var edited = 0;
  for (final _CorpusFixture fixture in _corpus) {
    if (await _verifyFixtureForRule(rule, fixable, validator, tempRoot, fixture)) {
      edited++;
    }
  }
  // Without this, a fix that never changes anything would pass P1 and P2.
  expect(edited, greaterThan(0), reason: '${rule.name} edited no fixture; add one it can fix');
}

/// Checks P1 and P2 for [rule] on [fixture], and returns whether the fix
/// changed the fixture.
Future<bool> _verifyFixtureForRule(
  SkillRule rule,
  FixableRule fixable,
  Validator validator,
  Directory tempRoot,
  _CorpusFixture fixture,
) async {
  final Directory skillDir = await _materialize(tempRoot, fixture);
  final ValidationResult before = await validator.validate(skillDir);
  final SkillContext? initialContext = before.context;
  if (initialContext == null) {
    return false;
  }

  final String once = await fixable.fix(initialContext);
  if (once == initialContext.rawContent) {
    return false;
  }

  final String nameAfterFix =
      SkillFixer.newDirectoryName(originalContent: initialContext.rawContent, fixedContent: once) ??
      initialContext.activeDirectoryName;
  final ValidationResult afterOnce = await validator.validateProposedContent(
    initialContext,
    once,
    activeDirectoryName: nameAfterFix,
  );

  // P1: applying the rule's fix a second time changes nothing.
  final String twice = await fixable.fix(afterOnce.context!);
  expect(twice, once, reason: '${rule.name} was not idempotent on ${fixture.label}');

  // P2: when a fix changes content, the rule's own diagnostic count drops.
  final int countBefore = before.validationErrors.where((e) => e.ruleId == rule.name).length;
  final int countAfter = afterOnce.validationErrors.where((e) => e.ruleId == rule.name).length;
  if (countBefore > 0) {
    expect(
      countAfter,
      lessThan(countBefore),
      reason: '${rule.name} edited ${fixture.label} without lowering its diagnostics',
    );
  }
  return true;
}

Future<void> _verifyConfigConvergence(_NamedConfig config) async {
  final Directory tempRoot = await Directory.systemTemp.createTemp('fix_p3_p4.');
  addTearDown(() => tempRoot.delete(recursive: true));

  final validator = Validator(ruleConfigs: config.ruleConfigs);
  final Map<String, RuleConfigPatch> patches = {
    for (final MapEntry(:key, :value) in config.ruleConfigs.entries)
      key: RuleConfigPatch(severity: value.severity, parameters: value.parameters),
  };

  for (final _CorpusFixture fixture in _corpus) {
    final Directory skillDir = await _materialize(tempRoot, fixture);
    final ValidationResult initial = await validator.validate(skillDir);
    final FixOutcome predicted = await SkillFixer(
      validator: validator,
      applyIgnores: (_) {},
      onFixFailed: (ruleName, error) => fail('$ruleName fix threw $error'),
    ).fix(initial);

    // P3a: the fixes settle before the pass limit.
    expect(predicted.settled, isTrue, reason: '${config.label} on ${fixture.label}');

    await validateSkillsInternal(
      individualSkillPaths: [skillDir.path],
      fixApply: true,
      quiet: true,
      resolvedRuleConfigs: patches,
    );

    final fixedDir = Directory(p.join(skillDir.parent.path, predicted.directoryName));
    expect(
      fixedDir.existsSync(),
      isTrue,
      reason: 'Expected directory ${predicted.directoryName} for ${fixture.label}',
    );
    final String diskContent = File(p.join(fixedDir.path, 'SKILL.md')).readAsStringSync();

    // P4: dry-run prediction matches on-disk content, directory name, and diagnostics.
    expect(diskContent, predicted.content, reason: '${config.label} on ${fixture.label}');
    final ValidationResult onDisk = await validator.validate(fixedDir);
    expect(
      _activeDiagnostics(onDisk),
      _activeDiagnostics(predicted.result),
      reason: '${config.label} on ${fixture.label}',
    );

    // P3b: a second `--fix` run changes nothing on disk.
    await validateSkillsInternal(
      individualSkillPaths: [fixedDir.path],
      fixApply: true,
      quiet: true,
      resolvedRuleConfigs: patches,
    );
    expect(fixedDir.existsSync(), isTrue);
    expect(File(p.join(fixedDir.path, 'SKILL.md')).readAsStringSync(), diskContent);
  }
}

void main() {
  test('RuleRegistry has built-in FixableRules', () {
    expect(_fixableRules, isNotEmpty);
  });

  group('P1 idempotent and P2 progress per FixableRule', () {
    for (final SkillRule rule in _fixableRules) {
      test(
        '${rule.name} is idempotent and lowers its own diagnostics when it edits',
        () => _verifyRuleProperties(rule),
      );
    }
  });

  group('P3 convergence and P4 dry-run == apply across config matrix', () {
    for (final _NamedConfig config in _configMatrix) {
      test(
        'converges in <= 2 passes and dry-run matches apply (${config.label})',
        () => _verifyConfigConvergence(config),
      );
    }
  });
}
