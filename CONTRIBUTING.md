# How to Contribute

We'd love to accept your patches and contributions to this project. There are
just a few small guidelines you need to follow.

## Contributor License Agreement

Contributions to this project must be accompanied by a Contributor License
Agreement (CLA). You (or your employer) retain the copyright to your
contribution; this simply gives us permission to use and redistribute your
contributions as part of the project. Head over to
<https://cla.developers.google.com/> to see your current agreements on file or
to sign a new one.

You generally only need to submit a CLA once, so if you've already submitted one
(even if it was for a different project), you probably don't need to do it
again.

## Code Reviews

All submissions, including submissions by project members, require review. We
use GitHub pull requests for this purpose. Consult
[GitHub Help](https://help.github.com/articles/about-pull-requests/) for more
information on using pull requests.

## Coding style

The Dart source code in this repo follows the:

  * [Dart style guide](https://dart.dev/guides/language/effective-dart/style)

You should familiarize yourself with those guidelines.

## File headers

All files in the Dart project must start with the following header; if you add a
new file please also add this. The year should be a single number stating the
year the file was created (don't use a range like "2011-2012"). Additionally, if
you edit an existing file, you shouldn't update the year.

    // Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
    // for details. All rights reserved. Use of this source code is governed by a
    // BSD-style license that can be found in the LICENSE file.

## Embedding the linter in tests

If your project already uses `skills_lint`, you can also call it
from your own test suite — handy when you want skill validation to fail
the same Dart-test pipeline that already gates the rest of your code:

```dart
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  test('Run skills linter', () async {
    // Load whatever's in skills_lint.yaml so the CLI and tests
    // share configuration. Pass `customRules: [...]` to inject any
    // custom SkillRule implementations.
    final config = await ConfigParser.loadConfig();
    expect(
      config.directoryConfigs,
      isNotEmpty,
      reason: 'Configuration directoryConfigs should not be empty.',
    );
    await validateSkills(config: config);
  });
}
```

`Validator` and `ValidationResult` are also exposed for tests that
need to inspect errors programmatically. Custom rule authoring lives
in the
[`skills-lint-validation`](packages/skills_lint/skills/skills-lint-validation/SKILL.md)
skill.

## Dart SDK on `PATH`

Non-interactive shells, such as an agent's persistent terminal, do not load your
shell profile. If `dart` is not found there, put the SDK on `PATH` first:

```bash
export PATH="/path/to/dart-sdk/bin:$PATH"
dart run bin/skills_lint.dart
```

## Testing and coverage

Run the test suite from the package root (`packages/skills_lint`):

```bash
dart test
```

### Where tests go

The package has two test roots, side by side in `packages/skills_lint/`:

| Directory | What goes there | A change to … can break it |
| :--- | :--- | :--- |
| `test/` | Tests of the shipped skills_lint package: rules, the CLI, configuration, the fixer, the install script and the public API. | `lib/`, `bin/` |
| `repo_test/` | Scans that fail when the repo drifts: file headers, the CI workflow, docs that must match the code (`RULES.md`, the README recipes), skill and eval structure, and source conventions. | anything in the repository |
| `repo_test/checkers/` | Unit tests of the checker code in `repo_test/src/`, run on inline snippets or temporary directories instead of the real repository. | `repo_test/src/` |
| `repo_test/src/` | Checker code shared by `repo_test/` and `repo_test/checkers/`. Not tests. | n/a |

Helpers that only package tests use stay in `test/`, such as
`test/test_utils.dart`.

This follows the `integration_test/` pattern in the
[package layout conventions](https://dart.dev/tools/pub/package-layout): a
second test directory next to `test/`, which plain `dart test` does not run.

```bash
dart test             # test/ only. CI measures coverage here.
dart test repo_test   # repo_test/, including repo_test/checkers/
```

CI runs the two as separate steps, so a failure shows which kind broke.
`repo_test/test_files_run_in_ci_test.dart` fails if a test file sits outside
`test/` and `repo_test/`, because no CI step would run it. The directories
that repo tests read are listed, with the reason for each subset, in
`repo_test/src/package_directories.dart`.

The repo tests share this package's `dev_dependencies`. When one needs a dev
dependency that no package test uses, move `repo_test/` to its own unpublished
workspace package (for example `packages/repo_checks/`) instead of adding the
dependency here.

### Testing the compiled CLI

CI also compiles the CLI with `dart compile exe` on Linux, macOS and Windows,
and runs the CLI tests against the executable. A CLI test starts the CLI with
`startCli` from `test/test_utils.dart`, and its library is tagged `cli`:

```dart
@Tags(['cli'])
library;
```

`startCli` runs the executable named by the `SKILLS_LINT_EXECUTABLE`
environment variable, or `dart bin/skills_lint.dart` when it is not set.
`repo_test/cli_runs_convention_test.dart` fails if a file in `test/` names
`bin/skills_lint.dart` itself, or calls `startCli` without the tag. To run the
CLI tests against an executable locally:

```bash
dart compile exe bin/skills_lint.dart -o /tmp/skills_lint
SKILLS_LINT_EXECUTABLE=/tmp/skills_lint dart test --tags=cli
```

### Coverage

CI enforces a minimum line-coverage threshold for `lib/` (currently 73%),
excluding generated `*.g.dart` files. To reproduce the same number locally:

```bash
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --ignore-files='**/*.g.dart'
```

The `--ignore-files='**/*.g.dart'` flag drops generated files from the report so
your local total matches the threshold CI enforces (CI applies the same
exclusion via the `very_good_coverage` action's `exclude` input). Omit the flag
to include generated files.

CI feeds `coverage/lcov.info` to the
[`very_good_coverage`](https://github.com/VeryGoodOpenSource/very_good_coverage)
GitHub Action, which fails the build when coverage falls below the threshold.
The threshold ratchets against regressions: when you raise overall coverage,
bump `min_coverage` in `.github/workflows/skills_lint_workflow.yaml` to
lock in the gain. To inspect coverage locally, render `coverage/lcov.info` with
`genhtml` or an editor LCOV viewer.

## Benchmarks

A separate workflow benchmarks the CLI on pull requests that change
`bin/`, `lib/` or `pubspec.yaml`. It never blocks a merge; a possible
slowdown shows as a warning annotation and in the job summary. The job
summary also times each rule on its own. If you add a rule, check its
time there. To run the benchmarks locally or to read the report, see
[`packages/skills_lint/benchmark/README.md`](packages/skills_lint/benchmark/README.md).

## Community Guidelines

This project follows
[Google's Open Source Community Guidelines](https://opensource.google/conduct/).

We pledge to maintain an open and welcoming environment. For details, see our
[code of conduct](https://dart.dev/code-of-conduct).

## Rule-stability policy (SemVer)

Lint rules are part of `skills_lint`'s public API. Adopters wire
the linter into pre-commit hooks and CI gates, so a rule that silently
flips from "warning" to "error" can break a downstream build with no
code change of their own. We version rule changes the same way we
version code changes:

- **Patch release (`0.3.X` → `0.3.X+1`, `1.0.X` → `1.0.X+1`)** —
  bug fixes to existing rules, including diagnostic message
  rewording, internal refactors, and fixes that *narrow* what a rule
  matches (fewer false positives). The set of error states a passing
  skill needs to clear does not grow.

- **Minor release (`0.3.X` → `0.4.0`, `1.0.X` → `1.1.0`)** — new
  rules, **shipping with `defaultSeverity: AnalysisSeverity.disabled`**
  so existing skills keep passing. Adopters opt in by enabling the
  rule via flag or YAML config. Performance improvements that don't
  change diagnostics also land here. A rule's diagnostic message may
  expand to include additional context.

- **Major release (`0.X` → `1.0`, `1.X` → `2.0`)** — any change that
  can fail a previously-passing skill: removing a rule (so configs
  referencing it stop working), upgrading a rule's default severity
  (`disabled → warning`, `warning → error`), broadening what a rule
  matches (more true positives = more failures), or renaming a rule.
  Releases bump the major version and the CHANGELOG calls out the
  exact rules affected.

Rationale: adopters should be able to set `skills_lint: ^1.0.0`
in `pubspec.yaml` and trust that a `dart pub upgrade` never turns
green CI red without their consent. Surprises belong in major
releases, and only there.

If you're proposing a change that doesn't fit cleanly into one of the
buckets above, say so on the PR and the maintainers will decide where
it lands. New built-in rules **must** include a `## <rule-name>`
entry in `RULES.md` describing default severity and behavior — see
the existing entries for the expected shape.
