# Agent Guidelines for skills_lint.dart

## Repository Architecture & Execution Context

- **Workspace Layout**: This repository is structured as a Dart workspace. The package code, tests, and configuration reside in `packages/skills_lint/`.
- **Package & CLI Name**: The package and CLI command is `skills_lint` (entrypoint `bin/skills_lint.dart`). Invoke locally via `dart run skills_lint` (never `skills_lint:cli`).
- **Running Tests**: Run tests from the package directory:
  ```bash
  cd packages/skills_lint && dart test
  ```

## Non-Negotiable Guardrails

- **Tool-Managed Configs**: NEVER manually edit `skills_config.json` files. These are strictly managed by the `skills` CLI (`skills add`).
- **Third-Party Skills**: All external skills live in root `third_party/skill-repos/<repo-slug>/` and are linked into `packages/skills_lint/.agents/skills/` via relative symlinks. Never replace symlinks with plain directories.
- **Internal Skills**: All internal skills in `packages/skills_lint/.agents/skills/` must declare `metadata: internal: true` in their frontmatter.
- **Branch Discipline**: Never commit or push directly to `main`. Always work on feature branches and create pull requests.
- **Lockfiles**: `pubspec.lock` is excluded from git for this library package.

## Skill Updates & Evaluation Requirements

Whenever adding or updating an agent skill:
1. Run the skill's evaluation suite defined in `<skill-name>/evals/evals.json`.
2. The resulting pull request description **must include**:
   - **Evaluation Results**: Full grading breakdown and pass/fail summary.
   - **Environment Description**: The model (e.g. Gemini 1.5 Pro, Claude 3.5 Sonnet) and harness configuration used during the eval run.

## Downstream Integration

- Agents are not required to test downstream consumers for routine changes, but can run downstream validation (e.g. against `flutter/flutter` via `check-downstream-consumers` / `dart-skills-lint-integration`) for complex migrations or breaking API/CLI changes.

## Code Standards & Tested Documentation

- **Cognitive Complexity**: Maximum cognitive complexity per function is **20** (checked in CI). Keep functions concise and decomposed.
- **Copyright Headers**: All `.dart` files must include the standard Dart copyright header.
- **README as Code**: Recipe code blocks in root `README.md` are structurally parsed and tested by `test/recipe_drift_test.dart`.

## Quality Gates

Before submitting any PR, ensure all gates pass:
```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
cd packages/skills_lint && dart test
```
