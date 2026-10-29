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
3.  **Metrics**: From the repository root, run `dart run cognitive_complexity --fail-threshold 20 --exclude 'third_party/**' --exclude 'packages/skills_lint/evals/test_data/**' --exclude '.worktrees/**' --exclude '.claude/**' .` and ensure there are zero issues.
4.  **Unused code**: From `packages/skills_lint`, run `dart run undead --fail-on-undead .` and `dart run undead --fail-on-undead ../../release` and ensure each exits 0.
5.  **Tests**: From `packages/skills_lint`, run `dart test`, `dart test repo_test`, and `dart test compiled_test`, and ensure all pass. If the change touches `release/`, also run Format, Analysis, and Tests in `release/`. See [Where tests go](../../../CONTRIBUTING.md#where-tests-go).
6.  **Skills**: If any skill files were modified, run `dart run skills_lint -d .agents/skills` to ensure they are valid.
7.  **Changelog**: Update `CHANGELOG.md` for user-facing CLI flags, package API changes, bug fixes, or user-facing behavior changes, following [Changelog sections](../../../CONTRIBUTING.md#changelog-sections). Do not log internal chores or message-wording tweaks; if internal-only, leave `CHANGELOG.md` untouched, output `[x] Changelog: (N/A) <reason>`, and add the `skip-changelog-check` label to the PR. Compare against the last released version, not intermediate PR commits.
8.  **Temporal**: Code, comments and docs describe the code as it is. They don't compare it with an earlier version or with your change. See [Temporal Words](../../../packages/skills_lint/documentation/knowledge/style_guide.md#temporal-words) for examples and the reason.
9.  **Documentation**: Update every document the change affects. If you change CLI flags, output, or config parsing, check `README.md`, `RULES.md`, and the other docs next to the code. Documented behavior must match the code.
10. **No Silent Deletions**: Diff the branch against its merge base. Name every removed comment, docstring, test, or eval assertion in the PR description, with the reason. Restore any removal you did not intend.
11. **Citations**: Open every URL the change adds. Each URL must resolve and support the claim it is attached to. Cite the Agent Skills specification only for rules the specification states.
12. **Comments**: Comments describe what the code does. Don't describe what isn't there, what a caller does, or work that was not done, unless someone is likely to redo it by accident.
13. **Doc scope**: Dartdoc states what callers rely on.
14. **API surface**: If the change adds or alters anything users or callers see, fill in the API surface section of the [PR description](../contributor-pr-description/SKILL.md).

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
