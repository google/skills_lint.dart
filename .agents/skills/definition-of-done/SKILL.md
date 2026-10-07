---
name: definition-of-done
description: Mandatory checks to run before completing any task that touches md files or dart code in this repository.
metadata:
  internal: true
---

# Definition of Done

Use this skill to ensure that all work meets the repository standards before declaring a task complete or requesting review.

## 📋 Mandatory Verification Steps

Before stating that a task is complete, you MUST execute and pass the following checks:

1.  **Format**: Run `dart format .` to format files, or `dart format --output=none --set-exit-if-changed .` to check without modifying. Ensure all files are formatted correctly.
2.  **Analysis**: Run `dart analyze --fatal-infos` and ensure there are zero issues (including info-level issues).
    Then check new code against the [Style Guide](../../../packages/skills_lint/documentation/knowledge/style_guide.md) for rules the analyzer cannot check.
3.  **Metrics**: From the repository root, run `dart run cognitive_complexity --fail-threshold 20 --exclude 'third_party/**' --exclude 'packages/skills_lint/evals/test_data/**' .` and ensure there are zero issues. This checks the cognitive complexity of every Dart file except vendored code in `third_party/` and the eval inputs in `packages/skills_lint/evals/test_data/`. It is the exact command CI runs in [`.github/workflows/skills_lint_workflow.yaml`](../../../.github/workflows/skills_lint_workflow.yaml), and [`packages/skills_lint/repo_test/workflow_consistency_test.dart`](../../../packages/skills_lint/repo_test/workflow_consistency_test.dart) fails if the two differ.
4.  **Tests**: Run `dart test` from `packages/skills_lint` and ensure all tests pass successfully. This runs the tests of the shipped package in `test/`. Then run `dart test repo_test` for the repo tests in `repo_test/`. See [Where tests go](../../../CONTRIBUTING.md#where-tests-go) for where a new test belongs.
    If the change touches `release/`, also run the Format, Analysis and Tests checks in `release/`. The `test` job of [`.github/workflows/release.yaml`](../../../.github/workflows/release.yaml) runs them in CI.
5.  **Skills**: If any skill files were modified, run `dart run skills_lint -d .agents/skills` to ensure they are valid.
6.  **Changelog**: If the task introduces user-facing CLI flags, package API changes, bug fixes, or user-facing behavioral changes, update `CHANGELOG.md`.
    - **Do NOT log internal chores**: Do not add entries for internal CI workflows, dev dependency updates/migrations, test refactoring, or repository infrastructure scripts.
    - **Explicit N/A**: If the task is internal-only, leave `CHANGELOG.md` untouched and output `[x] Changelog: (N/A) <reason>`.
    - **Label**: Internal-only PRs get the `skip-changelog-check` label. Without it, the Health changelog check fails the PR.
    - Audit all entries against the *previously released version* (do not document changes to intermediate PR development code or new unreleased APIs as breaking changes).
    - Write entries for users. Incidental fixes that no user would notice get no entry.
    - Changes to message wording get no entry.
7.  **Temporal**: Code, comments and docs describe the code as it is. They don't compare it with an earlier version or with your change. See [Temporal Words](../../../packages/skills_lint/documentation/knowledge/style_guide.md#temporal-words) for examples and the reason.
8.  **Documentation**: Update every document the change affects. If you change CLI flags, output, or config parsing, check `README.md`, `RULES.md`, and the other docs next to the code. Documented behavior must match the code.
9.  **No Silent Deletions**: Diff the branch against its merge base. Name every removed comment, docstring, test, or eval assertion in the PR description, with the reason. Restore any removal you did not intend.
10. **Citations**: Open every URL the change adds. Each URL must resolve and support the claim it is attached to. Cite the Agent Skills specification only for rules the specification states.
11. **Comments**: Comments describe what the code does. Don't describe what isn't there, what a caller does, or work that was not done, unless someone is likely to redo it by accident.
12. **Doc scope**: Dartdoc states what callers rely on.
13. **API surface**: If the change adds or alters anything users or callers see, fill in the API surface section of the [PR description](../contributor-pr-description/SKILL.md).

## 🚦 Output Formatting

You MUST include a text list of all mandatory verification steps in your final response to the user. Use the exact following format:
- Use `[x] <Identifier>: <Explanation>` if the step was completed.
- Use `[ ] <Identifier>: <Skipped explanation>` if the step was skipped or not applicable.

CRITICAL: Do not just copy the full step description text. You MUST use the exact bolded Identifier from the Mandatory Verification Steps list above, followed by a colon and your short explanation.

Examples:
- `[x] Format: dart format success.`
- `[x] Analysis: Static clean (0 issues, dart analyze --fatal-infos).`
- `[ ] Skills: Skipped because skills_lint is not installed.`
- `[x] Changelog: (N/A) Not necessary since we're updating internal eval fixtures.`
- `[x] Temporal: no added words.`
- `[x] Comments: new comments describe only what the code does.`
- `[x] Doc scope: dartdoc states only what callers rely on.`
