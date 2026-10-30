---
name: skills-lint-setup
description: |-
  Use this skill to set up skills_lint for the first time, either in a Dart package or as an installed command-line tool in any repository.
  Covers adding skills_lint as a dev dependency with a dart test that validates skills, installing the skills_lint command, and creating skills_lint.yaml.
  Don't use it to run the linter or fix its findings (use skills-lint-validation), or to set up CI such as GitHub Actions or SARIF code scanning.
---

# Setting up skills_lint

`skills_lint` is a linter for Agent Skills (`SKILL.md` files).

## Pick a setup path

If the user names a path, follow that one. Otherwise, inspect the project:

- If the project has a `pubspec.yaml`, follow
  [the dart test path](references/dart-test.md).
- Otherwise, follow [the command-line path](references/command-line.md).

## Create skills_lint.yaml

Both paths use a `skills_lint.yaml` file at the project root. The command
reads it from the current directory by default. Keep it short: list the skill
directories that exist, and only the rules whose severity you want to
change. Each path's reference file shows the configuration to use.

## Find the rules

Run `skills_lint --help`, or `dart run skills_lint --help` in a Dart package.
It lists every rule and option of the installed version, and which rules are
on by default.

## After setup

Use the skills-lint-validation skill to run the linter and fix failures.
