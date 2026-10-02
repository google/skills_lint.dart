# Changelog guide

The changelog is for the people who use the package. Each entry answers one
question: what changes for me if I upgrade?

## Entries

- Start with a past-tense verb: Added, Changed, Fixed, Removed, Deprecated.
- Name the flag, rule, option or API, in backticks.
- Say what a user sees, not how the code changed.
- Put breaking changes first, and start them with **Breaking:**.
- Link to the issue when there is one.

Good:

- Added the `--format sarif` option, which writes SARIF 2.1.0 for GitHub
  code scanning.
- **Breaking:** `--fix` now needs `--dry-run` to preview changes. Before, it
  printed them by default.
- Fixed `check-relative-paths` reporting links inside code blocks (#123).

Not useful:

- Refactored the validator.
- Updated dependencies.
- Fixed a bug.

## What to leave out

- Internal refactors, test changes and CI changes.
- Dependency updates that don't change behavior.
- Fixes to code that was never released.
- Changes to message wording.

## Sections

Use one section per version, newest first. The top section is `X.Y.Z-wip`
until the release, and gets its version when you publish.
