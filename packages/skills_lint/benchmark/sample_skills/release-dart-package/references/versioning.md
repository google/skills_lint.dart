# Versioning

Versions follow [semantic versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

## At 1.0.0 and above

| Change | Bump |
| --- | --- |
| Breaks the public API, a CLI flag, the config format or the output format | MAJOR |
| Adds a feature without breaking anything | MINOR |
| Fixes a bug without changing the API | PATCH |

## Below 1.0.0

Dart packages below 1.0.0 shift each level down by one:

| Change | Bump |
| --- | --- |
| Breaking change | MINOR, such as 0.5.3 to 0.6.0 |
| New feature or fix | PATCH, such as 0.5.3 to 0.5.4 |

## What counts as breaking

- Removing or renaming a public class, function, flag or config key.
- Changing a default, such as turning a rule on by default.
- Changing the exit code for the same input.
- Changing the JSON or SARIF output in a way that breaks a parser.

A new rule that is off by default is not breaking. A new rule that is on by
default is, because it can fail a build that passed before.

## Pre-release versions

Use `-wip` in the changelog and `pubspec.yaml` between releases, such as
`0.5.4-wip`. Never publish a `-wip` version.
