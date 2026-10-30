---
name: check-downstream-consumers
description: >
  Validates an in-progress PR or release candidate of skills_lint against known downstream ecosystem consumers, and rolls or upgrades skills_lint in downstream consumer repositories when requested.
  Use when assessing breaking changes across external repositories during PR evaluation, testing migrations against the changelog, determining backwards compatibility shims, or rolling a skills_lint commit ref or version into a downstream consumer repository.
  Do NOT use for day-to-day skill validation (use skills-lint-validation).
metadata:
  internal: true
---

# Check Downstream Consumers & Roll `skills_lint` Upgrades

Do NOT use for day-to-day skill validation (use [`skills-lint-validation`](../../../packages/skills_lint/skills/skills-lint-validation/SKILL.md)).

## Operating Modes

This skill supports two distinct operating modes:

- **Mode 1: Diagnostic PR Check (Default — No Downstream Commits)**
  Evaluates an in-progress `skills_lint` branch or release candidate against known downstream consumers to catch breaking changes, verify `@Deprecated` backward-compatibility shims, and validate [`packages/skills_lint/CHANGELOG.md`](../../../packages/skills_lint/CHANGELOG.md) migration instructions. All edits made inside downstream consumer checkouts during Mode 1 are strictly **diagnostic and transient**; restore every downstream checkout (`git restore .`) after evaluation and **never stage, commit, or push** code inside external repositories.
- **Mode 2: Downstream Roll / Upgrade PR (Only When Explicitly Requested)**
  Rolls a released version or target `skills_lint` commit `ref:` into a downstream consumer repository, updates centralized configuration and validation test harnesses, recalculates package hashes when required, and prepares a submission branch and pull request command for that consumer repository.

---

## 1. Preparation & Pre-Flight Repository Verification

1. **Verify Local Linter State (`skills_lint`)**
   - Run `git status` in `skills_lint` to confirm the working tree is clean.
   - Run `dart test` to confirm the `skills_lint` test suite passes.
   - Push the target commits to the remote branch so downstream consumers can resolve git hashes over the network.
   - Record the remote git SHA-1 commit hash (or released version tag) to test or roll.

2. **Locate & Sync Downstream Consumer Checkouts**
   - Read [`resources/known_consumers.md`](resources/known_consumers.md) to review known consumer repositories (`flutter/flutter`, `flutter/devtools`, `flutter/packages`, `dart-lang/site-www`, `dart-lang/skills`, `kevmoo/dash_skills`, etc.) and their consumption subdirectories.
   - **Discovering Local Checkouts**: If the local filesystem paths of these consumer repositories are not already known:
     1. **Check Workspace Knowledge**: Inspect active workspace definitions and machine-specific local Knowledge Items (`KIs`), which record configured directory layouts.
     2. **Inspect Adjacent Parent Directories**: Check sibling directories around the repository root (for example, listing adjacent directories under `..` or running depth-limited searches such as `find .. -maxdepth 3 -name pubspec.yaml`).
     3. **Ask Before Running Blind Traversals**: Never run unbounded root filesystem sweeps (`find / -name ...`). If a target repository is not found in adjacent workspace paths, ask the user whether the repository is checked out locally and request its path.
   - **Pre-Flight Consumer Sync**: Before modifying or testing any downstream checkout:
     1. Run `git status` to confirm the consumer repository has no active work in progress.
     2. Check out the primary tracking branch (`main` or `master`).
     3. Fast-forward from the authoritative upstream remote.
     4. If post-checkout hooks report engine or workspace updates (such as in `flutter/flutter`), run `gclient sync` before proceeding.

---

## 2. Updating the Dependency & Running Verification Tests

For each downstream consumer under evaluation or roll:

1. **Update `pubspec.yaml`**
   - Locate the target consumer package's `pubspec.yaml` (e.g., `dev/tools/pubspec.yaml` or `tool/pubspec.yaml`).
   - Update the `skills_lint` version constraint or pinned Git `ref:` field to the target commit hash:
     ```yaml
     skills_lint:
       git:
         url: https://github.com/google/skills_lint.dart
         path: packages/skills_lint
         ref: <TARGET_COMMIT_HASH>
     ```

2. **Resolve Dependencies & Run Baseline Tests (Backward-Compatibility Check)**
   - Resolve dependencies and run the consumer's validation entrypoint using the **Tooling Engine** and **Validation Entry Point** documented for that repository in [`resources/known_consumers.md`](resources/known_consumers.md) (for example, standard Dart consumers use `dart pub get` and `dart test`, Flutter consumers use `flutter pub get` and `flutter test`, and `flutter/flutter` requires the root-level package resolution and checksum commands documented under its entry in [`resources/known_consumers.md`](resources/known_consumers.md)).
   - Confirm whether existing validation tests and static analysis pass before modifying consumer call sites. Passing baseline tests confirm that `@Deprecated` shims preserve compatibility with existing consumer calls.

3. **Perform API Migration & Validation Harness Updates**
   - **Migrate Consumer Calling Syntax**: Update deprecated getters, parameters, or constructors in the consumer's validation entrypoint to use the current `skills_lint` API surface (for example, migrating `resolvedRules` to `resolvedRuleConfigs`).
   - **Centralized Configuration (`skills_lint.yaml`)**: Configure rules and target paths via `skills_lint.yaml` relative to the consumer repository root, keeping directory-level rules nested under a `rules:` map:
     ```yaml
     skills_lint:
       rules:
         check-relative-paths: error
         check-absolute-paths: error
         check-trailing-whitespace: error
       directories:
         - path: ".agents/skills"
     ```
   - **Validation Test Implementation Patterns**:
     - Follow [`validate_skills_example.dart`](../../../packages/skills_lint/skills/skills-lint-setup/references/validate_skills_example.dart): load `Configuration` via `ConfigParser.loadConfig()`, assert `expect(config.parsingErrors, isEmpty)` and `expect(config.directoryConfigs, isNotEmpty)`, and call `await validateSkills(config: config)`. When the test runner executes from a stable repository root, omit `skillDirPaths` so `validateSkills` uses the `directories:` and `individual_skills:` targets from `skills_lint.yaml`.
     - **Absolute Isolation Pattern in Sub-Package CI Runners**: When a downstream test harness changes working directories at runtime (such as CI runners executing inside sub-packages), pass `path: path.join(repoRoot.path, 'skills_lint.yaml')` to `ConfigParser.loadConfig(...)`. `ConfigParser.loadConfig` resolves `directoryConfigs`, `individualSkillConfigs`, and `ignore_file` relative to the directory containing `skills_lint.yaml`, so `await validateSkills(config: config)` works without passing `skillDirPaths` (pass `skillDirPaths: [path.join(repoRoot.path, ...)]` only when the consumer does not declare `directories:` in `skills_lint.yaml`, as `skillDirPaths` overrides `config.directoryConfigs` and drops `config.individualSkillConfigs`):
       ```dart
       import 'package:path/path.dart' as path;
       import 'package:skills_lint/skills_lint.dart';
       import 'package:test/test.dart';

       test('skills pass skills_lint', () async {
         final Configuration config = await ConfigParser.loadConfig(
           path: path.join(repoRoot.path, 'skills_lint.yaml'),
         );
         expect(
           config.parsingErrors,
           isEmpty,
           reason: 'Fix the skills_lint.yaml errors listed in this failure.',
         );
         expect(
           config.directoryConfigs,
           isNotEmpty,
           reason: 'skills_lint.yaml must list at least one skills directory.',
         );
         final bool passed = await validateSkills(config: config);
         expect(passed, isTrue);
       });
       ```
     - **Secondary Custom-Rule Test Blocks**: Prefer passing `customRules: [MyCustomRule()]` directly into the primary `validateSkills(config: config, customRules: [MyCustomRule()])` call (see [`skills-lint-validation`](../../../packages/skills_lint/skills/skills-lint-validation/SKILL.md)). If a consumer maintains a separate custom-rule-only test block without `skills_lint.yaml`, pass `skillDirPaths` explicitly and disable every built-in rule that is enabled by default in [`rule_registry.dart`](../../../packages/skills_lint/lib/src/rule_registry.dart) (`RuleRegistry.allChecks`) via `resolvedRuleConfigs` (`RuleConfigPatch(severity: AnalysisSeverity.disabled)`) so built-in rules do not run twice.
     - **Clean Up Resolved `TODO`s**: When upgrading an existing validation test block, audit adjacent `TODO` or issue-tracker comments and remove any comment whose config-loading refactor or tracked issue is resolved by the upgrade.
   - **Verify Public Boundary Resolution**: Run `dart analyze --fatal-infos <modified_test_or_package_path>` and `dart format` within the consumer package:
     - Confirm that every required class and parameter resolves through the public barrel (`import 'package:skills_lint/skills_lint.dart';`).
     - Any `Undefined class` error or requirement to import `package:skills_lint/src/...` indicates a **public export deficit** in [`lib/skills_lint.dart`](../../../packages/skills_lint/lib/skills_lint.dart).
   - **Re-run Consumer Test Suite**: Re-run the consumer's validation test suite using its **Tooling Engine** in [`resources/known_consumers.md`](resources/known_consumers.md) to verify that the migrated code passes.

---

## 3. Breaking Change Evaluation & Decision Protocol

When baseline or migrated tests fail, or when dependency resolution encounters API friction, pause and present the options to the human reviewer before deciding whether to mitigate in `skills_lint` or require a downstream migration.

### Analyzing the Failure
1. **Diagnose**: Identify the cause (renamed public parameters, removed model types, altered getter return types, or changed rule severity profiles).
2. **Mitigation Options**: Check whether a backward-compatible layer in `skills_lint` can bridge the change (`@Deprecated` getters, constructor parameter forwarding, or barrel exports).
3. **Changelog Integrity**: Verify whether the breaking change and its migration steps are documented in [`packages/skills_lint/CHANGELOG.md`](../../../packages/skills_lint/CHANGELOG.md).

### The Human Collaboration Point
Present the diagnostic summary to the human reviewer and choose one of the two pathways:

#### Pathway A: Backward-Compatibility Mitigation in `skills_lint` (Approved by Human)
1. Add the backward-compatible shim in `skills_lint` (such as `@Deprecated` getters/constructors or public barrel exports).
2. Add regression tests covering both deprecated consumer calls and current API calls, verifying that mutually exclusive parameters fail gracefully when combined.
3. Tag temporary shims with tracking issues (`// TODO(...)`) for removal in a future breaking release.
4. Run `dart format .`, `dart analyze --fatal-infos`, and `dart test` in `skills_lint`.
5. Commit and push the updated `skills_lint` branch, record the new commit SHA, update the downstream `pubspec.yaml`, and re-run consumer verification.

#### Pathway B: Downstream Migration via Changelog (Break Accepted)
1. **Attempt Downstream Upgrade**: Migrate the downstream consumer's calling code **strictly following the migration instructions in [`packages/skills_lint/CHANGELOG.md`](../../../packages/skills_lint/CHANGELOG.md)**.
2. **Evaluate Changelog Quality**: If the instructions in [`packages/skills_lint/CHANGELOG.md`](../../../packages/skills_lint/CHANGELOG.md) are incomplete or ambiguous during migration, treat the gap as an evaluation finding and propose targeted additions to [`packages/skills_lint/CHANGELOG.md`](../../../packages/skills_lint/CHANGELOG.md) so the migration steps are self-contained.
3. **Verify Build & Tests**: Re-run dependency resolution and the consumer's test suite until the downstream package passes cleanly.

---

## 4. Finalizing by Mode

### Mode 1 Finalization: Diagnostic Cleanup (Default — No Downstream Commits)
After evaluating each target repository in Mode 1:
1. **Restore Consumer Checkout**: Revert all diagnostic edits in the external consumer repository (`git checkout -- .` or `git restore .`) unless the user explicitly asks to keep uncommitted changes on disk for local inspection.
2. **Record Evaluation Summary**: Report which repositories passed unmodified, which required backward-compatibility shims in `skills_lint`, and which validated [`packages/skills_lint/CHANGELOG.md`](../../../packages/skills_lint/CHANGELOG.md) migration guidance.
3. **Check Reviewer Intent**: Ask the human reviewer whether to proceed to the next consumer in [`resources/known_consumers.md`](resources/known_consumers.md) or conclude the evaluation.

### Mode 2 Finalization: Downstream Roll PR Creation (Only When Requested)
When the user explicitly asks to roll `skills_lint` into a downstream consumer repository and prepare a roll PR:
1. **Stage & Commit on a Dated Roll Branch**:
   - Create a descriptive branch suffixed with the date in `YYYY-MM-DD` format (for example, `roll-skills-lint-YYYY-MM-DD`).
   - Verify `dart format`, `dart analyze --fatal-infos`, and any repository-specific **Tooling Engine** steps in [`resources/known_consumers.md`](resources/known_consumers.md) pass on all touched files.
   - Commit the dependency roll, configuration updates, and test harness changes with a concise commit message.
2. **Discover and Populate the Target Repository's PR Template**:
   - **Locate Template**: Search `.github/`, `.github/PULL_REQUEST_TEMPLATE/`, or the consumer repository root for `PULL_REQUEST_TEMPLATE.md` or `pull_request_template.md`.
   - **Extract & Populate Structure**: Read the discovered template and fill in every required section, issue link, and verification checklist (`[x]`) summarizing the `skills_lint` roll, configuration changes, and test updates.
   - **Fallback**: If the consumer repository has no PR template, construct a concise body summarizing the roll commit hash, configuration/test updates, and verification test results.
3. **Output or Execute the PR Command**:
   ```bash
   gh pr create \
     --title "Update skills_lint dependency to <hash> and centralize config" \
     --body "<populated repository template content>"
   ```
