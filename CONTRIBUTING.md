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

To run `skills_lint` from a package's own `dart test`, use the
`validateSkills` API as
[validate_skills_example.dart](packages/skills_lint/skills/skills-lint-setup/references/validate_skills_example.dart)
shows. The
[Dart test setup](packages/skills_lint/skills/skills-lint-setup/references/dart-test.md)
guide explains each step.

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

The package has three test roots, side by side in `packages/skills_lint/`:

| Directory | What goes there | A change to … can break it |
| :--- | :--- | :--- |
| `test/` | Tests of the shipped skills_lint package: rules, the CLI, configuration, the fixer, the install script and the public API. | `lib/`, `bin/` |
| `compiled_test/` | Runs the CLI tests from `test/` a second time, against a binary built by `dart compile exe`. Holds no tests of its own. | `lib/`, `bin/` |
| `repo_test/` | Scans that fail when the repo drifts: file headers, the CI workflow, docs that must match the code (`RULES.md`, the README recipes), skill and eval structure, and source conventions. | anything in the repository |
| `repo_test/checkers/` | Unit tests of the checker code in `repo_test/src/`, run on inline snippets or temporary directories instead of the real repository. | `repo_test/src/` |
| `repo_test/src/` | Checker code shared by `repo_test/` and `repo_test/checkers/`. Not tests. | n/a |

Helpers that only package tests use stay in `test/`, such as
`test/test_utils.dart`.

This follows the `integration_test/` pattern in the
[package layout conventions](https://dart.dev/tools/pub/package-layout): a
second test directory next to `test/`, which plain `dart test` does not run.

```bash
dart test                 # test/ only. CI measures coverage here.
dart test repo_test       # repo_test/, including repo_test/checkers/
dart test compiled_test   # the CLI tests, against the compiled CLI
```

CI runs the three as separate steps, so a failure shows which kind broke.
`repo_test/test_files_run_in_ci_test.dart` fails if a test file sits outside
`test/`, `repo_test/` and `compiled_test/`, because no CI step would run it.
The directories that repo tests read are listed, with the reason for each
subset, in `repo_test/src/package_directories.dart`.

The repo tests share this package's `dev_dependencies`. When one needs a dev
dependency that no package test uses, move `repo_test/` to its own unpublished
workspace package (for example `packages/repo_checks/`) instead of adding the
dependency here.

### Testing the compiled CLI

Releases ship the CLI built by `dart compile exe`, so the CLI tests run twice:
once from source with `dart test`, and once against the compiled binary with
`dart test compiled_test`. CI runs both on Linux, macOS and Windows.

A CLI test starts the CLI with `startCli` from `test/test_utils.dart`. It runs
`dart bin/skills_lint.dart`, except in `compiled_test/cli_test.dart`, which
compiles the binary in its setup, fails if compiling fails, and then calls the
shared tests. A test file whose tests all start the CLI is called through its
`main()`. A file that mixes CLI tests with other tests puts the CLI tests in a
`defineCliTests()` function, which both its `main()` and `compiled_test/` call.

`repo_test/dart_test_process_convention_test.dart` fails if a test starts the
Dart VM with `TestProcess.start` instead of calling `startCli`, because such a
test would skip the compiled binary.

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

## Releasing

See [RELEASING.md](RELEASING.md).

## Community Guidelines

This project follows
[Google's Open Source Community Guidelines](https://opensource.google/conduct/).

We pledge to maintain an open and welcoming environment. For details, see our
[code of conduct](https://dart.dev/code-of-conduct).

## Rule-stability policy (SemVer)

Lint rules are part of `skills_lint`'s public API. Adopters run the
linter in pre-commit hooks and CI gates, so a release can turn their
build red with no change of their own. The
[`dart-package-maintenance`](.agents/skills/dart-package-maintenance/SKILL.md)
skill defines the version numbers for each kind of release. This
section says which changes are breaking.

A change is breaking if it is likely to turn a real user's passing CI
red or to break real code that uses the package. Judge this by
evidence, not by what could break in theory. Evidence includes:

- the [known downstream consumers](.agents/skills/check-downstream-consumers/resources/known_consumers.md),
- a run of the linter over real `SKILL.md` files, such as those in
  [`third_party/skill-repos`](third_party/skill-repos/README.md), and
- a public code search for the API, flag or config key you change.

A change that reaches no real user is not breaking. Removing a public
API that nobody calls is not breaking. Neither is making a rule flag a
pattern that no real skill uses.

- **Major** — breaking changes. Changes to check for this are removing
  or renaming a rule, raising a rule's default severity
  (`disabled → warning`, `warning → error`), making a rule match more,
  changing the format of a rule's ignore subject, and removing or
  changing public API.

- **Minor** — new rules, changes to what a rule matches that aren't
  breaking, and other new features. New rules ship with
  `defaultSeverity: AnalysisSeverity.disabled` unless the evidence
  shows that enabling them fails no real skill. Speedups that don't
  change diagnostics also land here. A diagnostic message may add
  context.

- **Patch** — bug fixes to existing rules, including diagnostic
  message rewording, internal refactors, and fixes that make a rule
  match less (fewer false positives).

The CHANGELOG describes every change to what a rule reports and to
public API, breaking or not, and names the rules affected. Say on the
PR which evidence you checked.

Rationale: adopters should be able to set a caret constraint on
`skills_lint` in `pubspec.yaml` and trust that a `dart pub upgrade`
does not turn green CI red without their consent. Surprises belong in
major releases, and only there.

If you're proposing a change that doesn't fit cleanly into one of the
buckets above, say so on the PR and the maintainers will decide where
it lands. New built-in rules **must** include a `## <rule-name>`
entry in `RULES.md` describing default severity and behavior — see
the existing entries for the expected shape.

## Changelog sections

Each release in `packages/skills_lint/CHANGELOG.md` groups its entries
under these `###` headings, in this order. Leave out a heading that has
no entries.

- `### Breaking changes`: changes that the policy above finds breaking,
  such as a higher minimum Dart SDK or a removed rule that real configs
  use. Put a change that the policy finds not breaking under the heading
  that fits it best, and still describe it plainly.
- `### New rules`: rules the release adds.
- `### Behavior changes`: existing rules, errors and fixes that report
  more, less or differently.
- `### New features`: flags, config keys, rule parameters, output
  formats, API, skills, and speedups that don't change results.
- `### Bug fixes`: fixes that make the tool match its docs.

If a change makes a rule report differently because the old results were
wrong, it is a bug fix. If the old results matched the docs and the docs
change too, it is a behavior change.

Change only the `-wip` section. Released sections stay as published,
including the flat sections that have no headings.
`packages/skills_lint/repo_test/changelog_convention_test.dart` checks the
headings. The `released_changelog` job in
`.github/workflows/skills_lint_workflow.yaml` runs it with
`CHANGELOG_BASE_REF` set, so that it also checks that no released section
changes.
