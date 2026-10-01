---
name: add-repo-convention-check
description: >
  How to add a test that enforces a convention on this repository's own code,
  docs or config, such as a rule about imports, file layout, comments or
  CHANGELOG entries. Use when asked to add or extend a convention, hygiene or
  consistency check that scans the repository. Do not use for tests of
  skills_lint's behavior, or for a lint rule that users run on their skills
  (use add-dart-lint-validation-rule for that).
metadata:
  internal: true
---

# Add a Repo Convention Check

A convention check is a test that scans this repository and fails when code, docs or config break a rule that reviewers would otherwise enforce by hand. It tests the repository, not skills_lint's behavior.

Helpers go in `test/src/` (models in `test/src/models/`) and tests go in `test/`, and [issue #54](https://github.com/google/skills_lint.dart/issues/54) is where that layout is decided.

## Structure

- A detector takes a [`Source`](../../../packages/skills_lint/test/src/models/source.dart) and returns a list of [`ConventionViolation`](../../../packages/skills_lint/test/src/models/convention_violation.dart). Create each finding with `Source.violationAt`. Don't add a second finding type.
- Find and parse Dart files only through `parseDirectories` in [source_conventions.dart](../../../packages/skills_lint/test/src/source_conventions.dart). Don't write a second file walker.
- Unit-test each detector on inline snippets built with `Source.snippet`. Cover what it reports and what it ignores. For example, `findForbiddenOverrides` in [source_conventions.dart](../../../packages/skills_lint/test/src/source_conventions.dart) is tested in [source_convention_detectors_test.dart](../../../packages/skills_lint/test/source_convention_detectors_test.dart).
- Put the repo-wide scan in its own test file, apart from the detector tests. For example, [source_conventions_test.dart](../../../packages/skills_lint/test/source_conventions_test.dart).

## Dartdoc

- Say **why** the rule exists and **what would make us change it**. For example, [rule_file_convention_test.dart](../../../packages/skills_lint/test/rule_file_convention_test.dart).
- Justify every threshold in the dartdoc. Leave the number out of skills.

## Failure output

- Name each offending file or item, and say how to fix it. `expectNoViolations` in [source_conventions.dart](../../../packages/skills_lint/test/src/source_conventions.dart) prints one `path:line: problem` line per violation, then the fix.
- Never suggest how to get around the check.

## Allowlists

Keep one list per reason. For example, [test_coverage_convention_test.dart](../../../packages/skills_lint/test/test_coverage_convention_test.dart).

- **Trivial**: may grow, and only with a reason on each entry.
- **Covered elsewhere**: each entry names the test that covers it.
- **Should be fixed**: shrink-only. Each entry has `TODO(<owner>): <issue URL>`, and the test fails once an entry passes the check, so the entry gets removed.

## Pull request

Record the negative checks in the PR body: break a case on purpose, run the test, and paste its failure output.
