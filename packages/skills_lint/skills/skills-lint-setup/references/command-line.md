# Command-line setup

Use this path to run the installed `skills_lint` command, in a Dart package or
in any other repository.

## 1. Install skills_lint

Pick one:

- Homebrew (Linux and macOS, no Dart SDK needed):

  ```bash
  brew tap google/skills-lint https://github.com/google/skills_lint.dart
  brew install google/skills-lint/skills_lint
  ```

- The install script (Linux and macOS, no Dart SDK needed). It downloads the
  prebuilt binary from the latest GitHub release, checks its SHA256, and
  installs it to `/usr/local/bin`:

  ```bash
  curl -fsSL https://github.com/google/skills_lint.dart/releases/latest/download/install.sh | bash
  ```

  On macOS, the binary isn't code-signed yet. If Gatekeeper blocks the first
  run, remove the quarantine flag:

  ```bash
  xattr -d com.apple.quarantine "$(which skills_lint)"
  ```

- With the Dart SDK:

  ```bash
  dart install skills_lint
  ```

Homebrew and the install script download a binary from a GitHub release. If
that download fails, use `dart install skills_lint`.

Check the install with `skills_lint --version`.

## 2. Create skills_lint.yaml

Create `skills_lint.yaml` at the repository root. List each directory that
holds skills. For example:

```yaml
skills_lint:
  rules:
    check-relative-paths: error
  directories:
    - path: ".agents/skills"
```

## 3. Run it

From the repository root:

```bash
skills_lint
```

The command reads `skills_lint.yaml` from the current directory. Pass
`-c <path>` to use another configuration file. It exits with a nonzero code
when any skill has an error.

## 4. Fix what it reports

Some rules can fix their own findings:

```bash
skills_lint --fix --dry-run   # preview the changes
skills_lint --fix             # write them
```

Fix the rest by hand, then run `skills_lint` again until it passes.
