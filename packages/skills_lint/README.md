# skills_lint

This is not an officially supported Google product. This project is not
eligible for the [Google Open Source Software Vulnerability Rewards Program](https://bughunters.google.com/open-source-security).


A static analysis linter for Agent Skills to ensure they meet the specification in presubmit checks. This project is a Dart package and can be run as a CLI tool to validate your skills directory before committing.

## Table of Contents
- [Overview](#overview)
- [Installation](#installation)
- [Usage](#usage)
  - [Rule Precedence](#rule-precedence)
- [Built-in Rules](#built-in-rules)
- [Recipes](#recipes)
- [Contributing](#contributing)

## Overview

An **Agent Skill** is a portable, self-contained directory that extends an AI agent's capabilities. Pre-submit linting ensures that your skill definitions are valid and ready for consumption by agent platforms.

`skills_lint` validates:
- Presence of mandatory `SKILL.md` file.
- YAML frontmatter constraints (naming, length, etc.).
- Directory structure (flat, no deep nesting).
- Relative path integrity.

For a full definition of the skill standard, see the [Agent Skills Specification](https://agentskills.io/specification).

## Installation

`skills_lint` ships as both a standalone native binary (no Dart
SDK required) and as a Dart package on pub.dev. Pick the path that
matches your environment.

> **Homebrew note.** A `brew install dart-skills-lint` path is on the
> roadmap; it will land after `skills_lint` migrates to its own
> dedicated repository. Until then, the install paths below cover all
> supported platforms.

### 1. Dart developers — pub.dev

If you already have the Dart SDK installed, the standard pub.dev paths
still work and are unchanged.

#### As a project dev_dependency

Add to your `pubspec.yaml`:
```yaml
dev_dependencies:
  skills_lint: ^0.5.0
```

Then:
```bash
dart pub get
```

#### Globally installed

For multiple projects without per-project pubspec entries:
```bash
dart install skills_lint
```

### 2. `install.sh` — Linux + macOS, no Dart required

The recommended path for CI runners and laptops without the Dart SDK
on PATH. Downloads the matching prebuilt binary from the latest GitHub
Release, verifies its SHA256, and installs to `/usr/local/bin` (with a
`sudo` fallback). Supports macOS arm64 + x64 and Linux x64 + arm64.

```bash
curl -fsSL https://github.com/google/skills_lint.dart/releases/latest/download/install.sh | bash
```

Optional env vars (set before the `bash` part):
- `INSTALL_DIR` — install destination (default `/usr/local/bin`).
- `VERSION` — pin a specific release like `0.4.0` (default `latest`).
- `REPO` — alternate source repo (default `google/skills_lint.dart`).

#### macOS first-launch note

macOS binaries are not yet code-signed. The first time you run the
binary, macOS Gatekeeper will block it ("cannot be opened because the
developer cannot be verified"). Remove the quarantine flag once:

```bash
xattr -d com.apple.quarantine "$(which skills_lint)"
```

This step goes away once notarized builds ship.

### 3. Direct download — Linux + macOS, no install script

For environments where piping a script to `bash` isn't acceptable.
Grab the tarball for your platform from
[the latest GitHub Release](https://github.com/google/skills_lint.dart/releases/latest)
and verify its SHA256 against the release's `SHA256SUMS` asset.

```bash
TARGET="linux-x64"     # or: macos-arm64, macos-x64, linux-arm64
VERSION="0.5.0"
BASE="https://github.com/google/skills_lint.dart/releases/download/skills_lint-v${VERSION}"
curl -fsSLO "${BASE}/skills_lint-${TARGET}.tar.gz"
curl -fsSLO "${BASE}/SHA256SUMS"
grep " skills_lint-${TARGET}.tar.gz$" SHA256SUMS | sha256sum -c -
tar -xzf "skills_lint-${TARGET}.tar.gz"
sudo install -m 0755 "skills_lint-${TARGET}" /usr/local/bin/skills_lint
```

On macOS, replace `sha256sum -c -` with `shasum -a 256 -c -`.

## Usage

`skills_lint` runs as a command-line tool, configured by flags or by
a `skills_lint.yaml` file. The CLI is the user-facing surface; it
also has a programmatic API for contributors who need to embed the
linter in their own test suite — see
[`CONTRIBUTING.md`](CONTRIBUTING.md#embedding-the-linter-in-tests).

### 1. As a Command Line Tool with Arguments
Run the linter against your skills or root skills directories by passing arguments.

```bash
dart run skills_lint --skills-directory ./path/to/skills-root
```

Multiple root directories can be specified:
```bash
dart run skills_lint --skills-directory ./path/to/root-a --skills-directory ./path/to/root-b
```

Validate Individual Skills directly using `--skill` or `-s`:
```bash
dart run skills_lint --skill ./path/to/my-single-skill
```

If no directory is specified, it automatically checks `.claude/skills` and `.agents/skills` relative to your workspace root.

### Flags
- `-d`, `--skills-directory`: Specifies a root directory containing sub-folders of skills to validate. Can be passed multiple times. Can use home tilde expansion (ex: `~/.agents/skills`).
- `-s`, `--skill`: Specifies an individual skill directory to validate directly. Can be passed multiple times.
- `-q`, `--quiet`: Hide non-error validation output.
- `-w`, `--print-warnings`: Enable printing of warning messages.
- `--fast-fail`: Halt execution immediately on the error.
- `-c`, `--config`: Path to a configuration file. Defaults to `skills_lint.yaml` in the current directory. Paths declared inside a configuration file resolve relative to that file's directory.
- `--ignore-config`: Ignore the YAML configuration file entirely.
- `--ignore-file`: Path to a JSON file listing lints to ignore for the run.
- `--generate-baseline`: Write every current error into `skills_lint_ignore.json` so existing violations are ignored on future runs.
- `--[no-]check-trailing-whitespace`: Enable/disable checking for trailing whitespace. (Disabled by default).
- `--[no-]published-skill-name`: Enable/disable checking that published package skills follow the package naming convention. (Disabled by default).
- `--fix`: Write fixes for failing lints to disk.
- `--dry-run`: When combined with `--fix`, prints the proposed diff without writing.
- `--fix-apply`: *Deprecated* alias for `--fix`. Prints a deprecation notice on use.
- `--format`: Output format for validation diagnostics. One of:
  - `text` (default): human-readable terminal output.
  - `json`: a machine-readable JSON array of validation results.
  - `sarif`: a SARIF 2.1.0 document for CI and GitHub Code Scanning. See
    [Recipe: GitHub Code Scanning](#recipe-github-code-scanning-sarif).

  Diagnostics go to standard output in every format, so redirect them to a
  file to capture a report: `skills_lint --format=sarif > skills-lint.sarif`.
  Operational failures stay on standard error, prefixed with
  `skills_lint internal error:`, and never corrupt the report.

### 2. As a Command Line Tool with a YAML Configuration File
You can configure the linter using a configuration file (defaulting to `skills_lint.yaml` in the current directory).

Create `skills_lint.yaml` in the root of your repository:

```yaml
# skills_lint.yaml
skills_lint:
  rules:
    check-relative-paths: error
    check-absolute-paths: error
  directories:
    - path: "~/.agents/skills"
      ignore_file: "~/.agents/skills/ignore.json"
  individual_skills:
    - path: "my_custom_standalone_skill"
      rules:
        missing_install_script: warning
      ignore_file: "my_ignores.json"
```

Then you can simply run:
```bash
dart run skills_lint
```

### Rule Precedence

When resolving which severity and parameters to apply for a rule, `skills_lint` evaluates settings in the following order of precedence (highest to lowest):

1. **CLI Flags / API Overrides**:
   - Rule severity overrides: Explicit flags passed to the CLI (e.g., `--check-trailing-whitespace` or `--no-check-trailing-whitespace`).
   - Rule parameter overrides: Namespaced command-line parameter flags (e.g., `--path-does-not-exist-exclude=".*-workspace"`). Passing an empty string (e.g. `--path-does-not-exist-exclude=""`) explicitly clears the custom parameter.
2. **Path-Specific Config**: Rules defined under `directories:` or `individual_skills:` in `skills_lint.yaml` for a matching path.
   - If a target config specifies a **map** (e.g. `path-does-not-exist: { severity: error, exclude: "..." }`), the parameters map completely overrides any global parameters for that rule.
   - If a target config specifies a **simple string** severity (e.g. `path-does-not-exist: error`), the severity is overridden, but the global parameters map is inherited/preserved.
3. **Global Config**: Rules and parameters defined under the top-level `rules:` in `skills_lint.yaml`.
4. **Defaults**: The hardcoded defaults for each rule.

This ensures that you can always override configuration file settings for a specific run by using CLI flags.

---

### 3. Custom Rules

Custom rule authoring lives in the
[`skills-lint-validation`](skills/skills-lint-validation/SKILL.md)
skill — that skill walks through extending `SkillRule` and passing the
rule into the linter.

## Built-in Rules

For the full list of built-in validation rules — default severities, exact
diagnostic shapes, auto-fix behavior, and configuration options — see
[`RULES.md`](RULES.md).

## Recipes

Drop-in snippets for the most common ways to wire `skills_lint` into a
project's quality gates. Each recipe is exercised by
[`test/recipe_drift_test.dart`](test/recipe_drift_test.dart), so if a
flag here goes stale, CI fails.

### Recipe: GitHub Actions

Save the following as `.github/workflows/lint-skills.yml`. It runs on
every push and PR, installs `skills_lint` globally on the runner,
and validates every skill under `.claude/skills/`. Adjust the path to
match where your skills live.

```yaml
# .github/workflows/lint-skills.yml
name: Lint Agent Skills
on:
  push:
    branches: [main]
  pull_request:

permissions: read-all

jobs:
  lint-skills:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: dart-lang/setup-dart@v1
      - run: dart install skills_lint
      - run: skills_lint --skills-directory ./.claude/skills
```

To validate a single skill directory instead, swap the last step:

```yaml
      - run: skills_lint --skill ./.claude/skills/my-skill
```

### Recipe: GitHub Code Scanning (SARIF)

`--format=sarif` emits a SARIF 2.1.0 document that GitHub Code Scanning
accepts, which surfaces each lint as an annotation on the pull request
diff and as an entry in the repository's Security tab. Save the
following as `.github/workflows/code-scanning.yml`.

```yaml
# .github/workflows/code-scanning.yml
name: Skills Code Scanning
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  scan-skills:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: dart-lang/setup-dart@v1
      - run: dart install skills_lint

      # The linter exits 1 when it finds violations. continue-on-error
      # lets the upload step run first, so findings reach Code Scanning
      # instead of disappearing with the failed job.
      - name: Generate SARIF report
        id: lint
        continue-on-error: true
        run: skills_lint --skills-directory ./.claude/skills --format=sarif > skills-lint.sarif

      # Pull requests from forks cannot write security events, so skip
      # the upload there rather than failing the job on a permission
      # error.
      - name: Upload SARIF report
        if: ${{ !cancelled() && steps.lint.conclusion != 'skipped' && (github.event_name != 'pull_request' || !github.event.pull_request.head.repo.fork) }}
        uses: github/codeql-action/upload-sarif@faaca9a8f6edddba5725ffe5adefdab6669a2eca # v3.38.0
        with:
          sarif_file: skills-lint.sarif
          category: skills_lint

      - name: Fail on lint violations
        if: steps.lint.outcome != 'success'
        run: exit 1
```

Notes:

- The report goes to standard output, so redirect it to a file.
  Operational failures go to standard error with a
  `skills_lint internal error:` prefix and never mix into the report.
- Result paths are recorded relative to the repository root using the
  SARIF `%SRCROOT%` base, so annotations land on the right lines even
  when the linter runs from a subdirectory.
- Code Scanning is available on public repositories and on private
  repositories with GitHub Advanced Security. Without it, the upload
  step fails; drop it and keep `--format=sarif` output as a build
  artifact instead.
- Use `--format=json` for a plain array of results when feeding a
  consumer other than Code Scanning.


### Recipe: Dart-native pre-commit hook

A pre-commit hook that calls into the linter directly — no Husky, no
Python `pre-commit` framework, just Dart and the existing
`dart install` tooling.

Install the linter globally once per machine:

```bash
dart install skills_lint
```

Then install the hook into the repository (run from the repo root):

```bash
cat > .git/hooks/pre-commit <<'HOOK'
#!/bin/sh
set -e
# Lint every skill under .claude/skills before each commit.
# Add --skill arguments for other locations as needed.
exec skills_lint --skills-directory ./.claude/skills --quiet
HOOK
chmod +x .git/hooks/pre-commit
```

The hook exits non-zero on lint failure, blocking the commit. To
auto-apply fixable lints inside the hook, append `--fix` to the linter
invocation.

### Recipe: have an agent set it up for you

If you're using Claude Code, Gemini, or another agent that can read
repository-local skills, paste the following prompt to have the agent
install and validate `skills_lint` for you. The agent will
follow the
[`skills-lint-setup`](skills/skills-lint-setup/SKILL.md)
skill for first-time wiring, then the
[`skills-lint-validation`](skills/skills-lint-validation/SKILL.md)
skill to run the linter and resolve any failures.

> Set up skills_lint in this project. Use the skill at
> `skills/skills-lint-setup/SKILL.md`
> to add it as a dev_dependency, create the configuration file,
> and wire it into CI. Then use the skill at
> `skills/skills-lint-validation/SKILL.md`
> to run the linter and resolve any failures.

## Contributing

Contributions are welcome! Please ensure that any PRs pass the linter and test suite.

