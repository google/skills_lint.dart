---
name: add-dart-lint-validation-rule
description: >
  Instructions for adding a validation rule and CLI flag to skills_lint.
  Use when asked to create a rule that validates aspects of skills
  (like frontmatter metadata).
metadata:
  internal: true
---

# Add a Validation Rule and Flag

Add a built-in validation rule to `skills_lint`, expose the rule as a CLI flag, and verify the rule's behavior.

## 1. Rule Class in `lib/src/rules/`

- Declare one public [`SkillRule`](../../../packages/skills_lint/lib/src/models/skill_rule.dart) subclass per file in `lib/src/rules/` ([`rule_file_convention_test.dart`](../../../packages/skills_lint/repo_test/rule_file_convention_test.dart)).
- Follow [`disallowed_field_rule.dart`](../../../packages/skills_lint/lib/src/rules/disallowed_field_rule.dart) (or [`description_length_rule.dart`](../../../packages/skills_lint/lib/src/rules/description_length_rule.dart) for parameterized rules): define `static const String ruleName`, `static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled` (per the [Rule-stability policy](../../../CONTRIBUTING.md#rule-stability-policy-semver)), and any parameter names, default values, and `ParameterConstraint` definitions as `static const` fields on the rule class.
- Name rule parameters in kebab-case without starting with a word from `ruleName`, because the CLI flag is `--<rule>-<param>` ([`rule_parameter_naming_test.dart`](../../../packages/skills_lint/repo_test/rule_parameter_naming_test.dart)).
- Read YAML frontmatter from `context.parsedYaml` and map nodes to source spans with `context.yamlNodeToRegion`.
- Cite [`SpecificationUrls`](../../../packages/skills_lint/lib/src/specification_urls.dart) only when the rule enforces the official Agent Skills specification.
- Implement [`FixableRule`](../../../packages/skills_lint/lib/src/fixable_rule.dart) when the rule supports `--fix`.

## 2. Registration in [`lib/src/rule_registry.dart`](../../../packages/skills_lint/lib/src/rule_registry.dart)

- Add a `CheckType` to `RuleRegistry.allChecks` (with `parameterSchema` and `parameterConstraints` when parameterized; add a rejected test value in [`test/parameter_constraint_test.dart`](../../../packages/skills_lint/test/parameter_constraint_test.dart)).
- Add a case in `RuleRegistry.createRule` that passes `severity` and any parsed `parameters` (falling back to the rule's default constants) to the rule constructor.
- Enable the rule in `fixtureConfig` and add a planted violation to `violations` and `plantedViolations` in [`benchmark/src/fixture.dart`](../../../packages/skills_lint/benchmark/src/fixture.dart) ([`test/benchmark/fixture_test.dart`](../../../packages/skills_lint/test/benchmark/fixture_test.dart)).

## 3. Tests in `packages/skills_lint/test/`

- Add unit tests in `packages/skills_lint/test/<rule_name>_test.dart` (or `test/rules/<rule_name>_test.dart`; [`test_coverage_convention_test.dart`](../../../packages/skills_lint/repo_test/test_coverage_convention_test.dart) scans `packages/skills_lint/test/` recursively for a test importing the rule).
- Give minimal `SKILL.md` test fixtures valid required frontmatter (`name` and `description`) unless testing missing frontmatter.
- Use `Directory.systemTemp.createTemp` (cleaned up in `tearDown`) when testing filesystem rules (see [`path_does_not_exist_rule_test.dart`](../../../packages/skills_lint/test/rules/path_does_not_exist_rule_test.dart)), or [`createTestSkillContext`](../../../packages/skills_lint/test/test_utils.dart) when testing frontmatter or content rules with an in-memory `SkillContext` so `parsedYaml` is populated.
- Test that each rule parameter changes what the rule reports. [`rule_settings_supply_test.dart`](../../../packages/skills_lint/test/rule_settings_supply_test.dart) automatically tests config-file, CLI, and Dart API supply and precedence for every registered rule and parameter in `RuleConfig`; if a rule reads a setting from anywhere other than its `RuleConfig`, test each way that setting can be supplied.
- For CLI tests, use `startCli` from [`test/test_utils.dart`](../../../packages/skills_lint/test/test_utils.dart) and wire `defineCliTests()` into [`compiled_test/cli_test.dart`](../../../packages/skills_lint/compiled_test/cli_test.dart) ([`cli_test_wiring_convention_test.dart`](../../../packages/skills_lint/repo_test/cli_test_wiring_convention_test.dart)).

## 4. Documentation and Verification

- Add a `## <rule-name>` entry in [`RULES.md`](../../../packages/skills_lint/RULES.md) ([`rules_md_consistency_test.dart`](../../../packages/skills_lint/repo_test/rules_md_consistency_test.dart)).
- Add `- \`--[no-]<rule-name>\`: <description>. (Disabled by default).` (omitting `(Disabled by default).` only when enabled by default) under Flags in [`README.md`](../../../packages/skills_lint/README.md); match `ruleName` exactly and don't add a `check-` prefix.
- Add an entry under `### New rules` in [`CHANGELOG.md`](../../../packages/skills_lint/CHANGELOG.md).
- Run [`definition-of-done`](../definition-of-done/SKILL.md).
