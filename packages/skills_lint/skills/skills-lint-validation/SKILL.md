---
name: skills-lint-validation
description: |-
  Use this skill to execute skills_lint validation and resolve rule violations across AI agent skills.
  Covers running the CLI validator, analyzing diagnostic failures, applying automated fixes with --fix, and authoring custom SkillRule classes in Dart.
---

# Validating Skills with skills_lint

This skill covers **day-to-day use**: running the linter, walking
through a failing run, and writing a custom rule when defaults
aren't enough. For first-time wiring (adding the dep, creating the
config file, generating a baseline) use the
skills-lint-setup skill. The full rule reference (default severities,
diagnostic shapes, fixability) lives in [`RULES.md`](../../RULES.md).

## Running the linter

If `skills_lint` is in `pubspec.yaml`:

```bash
dart run skills_lint -d .agents/skills
```

If it's installed globally with `dart install`:

```bash
skills_lint -d .agents/skills
```

Run `dart run skills_lint --help` (or `skills_lint --help`) for the full flag list
(skip the inline duplicate so it never goes stale).

## Workflow for a failing run

1. **Run the validator.**
2. **Read the errors.** Each diagnostic names the rule that fired,
   the offending value, and a suggested fix when one applies.
3. **Fix the violations.** For fixable rules
   (`check-absolute-paths`, `check-trailing-whitespace`,
   `invalid-skill-name`), pass `--fix` to write the corrections
   to disk; add `--dry-run` to preview the diff first.
4. **Re-run** to confirm the run is clean.

### Task progress

- [ ] Run validator
- [ ] Read errors
- [ ] Fix violations (manual or `--fix` / `--fix --dry-run`)
- [ ] Verify clean run

## Authoring a custom rule

Extend `SkillRule` and pass the rule into `validateSkills`:

```dart
import 'package:skills_lint/skills_lint.dart';

class DeprecatedSkillRule extends SkillRule {
  @override
  final String name = 'deprecated-skill';

  @override
  final AnalysisSeverity severity = AnalysisSeverity.warning;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    return switch (context.parsedYaml) {
      {'metadata': {'deprecated': true}} => [
        ValidationError(
          ruleId: name,
          severity: severity,
          file: 'SKILL.md',
          message: 'This skill is marked as deprecated.',
        ),
      ],
      _ => [],
    };
  }
}
```

Wire it up in a Dart test:

```dart
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  test('skills pass with deprecated-skill custom rule', () async {
    final Configuration config = await ConfigParser.loadConfig();
    expect(
      config.directoryConfigs,
      isNotEmpty,
      reason: 'Configuration directoryConfigs should not be empty.',
    );
    final bool passed = await validateSkills(
      config: config,
      customRules: [DeprecatedSkillRule()],
    );
    expect(passed, isTrue, reason: 'skills_lint found errors. Its findings are printed above.');
  });
}
```

A rule in `customRules` keeps the severity it was built with. To let
`skills_lint.yaml` set its severity and parameters, as it does for built-in
rules, give the rule a `severity` constructor parameter and pass a
`RuleDefinition` in `customRuleDefinitions` instead:

```dart
final bool passed = await validateSkills(
  config: config,
  customRuleDefinitions: [
    RuleDefinition(
      check: const CheckType(
        name: 'deprecated-skill',
        defaultSeverity: AnalysisSeverity.warning,
        help: 'Check for skills marked as deprecated.',
      ),
      create: (severity, parameters) => DeprecatedSkillRule(severity: severity),
    ),
  ],
);
```

Then `rules: {deprecated-skill: error}` in `skills_lint.yaml` makes it an error.

## Related

- The skills-lint-setup skill — first-time wiring.
- [`RULES.md`](../../RULES.md) — canonical rule reference.
- [`README.md`](../../README.md) — installation, configuration,
  integration recipes.
