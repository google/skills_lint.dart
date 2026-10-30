# Dart test setup

Use this path for a Dart package. `dart test` then fails when a skill is invalid.

## 1. Add the dependencies

From the package root:

```bash
dart pub add dev:skills_lint dev:test
```

Skip `dev:test` if `pubspec.yaml` already lists `test`.

## 2. Create skills_lint.yaml

Create `skills_lint.yaml` at the package root, next to `pubspec.yaml`. List
only skill directories that exist. A directory that is listed but missing
fails the test.

If the package has no `skills/` directory at its root, it doesn't publish
skills. List only its other skill directories, such as `.agents/skills`:

```yaml
skills_lint:
  directories:
    - path: ".agents/skills"
```

If the package has a `skills/` directory at its root, it publishes the skills
in it. Add a `skills` entry with the rules for published skills:

```yaml
skills_lint:
  directories:
    - path: "skills"
      rules:
        pub-archive-includes-skill: error
        published-skill-name: error
        check-relative-paths:
          severity: error
          within-skill: true
```

Add a `.agents/skills` entry next to it only if that directory exists. The
rules under `skills` are only for published skills:

- `check-relative-paths` checks that every relative link resolves.
  `within-skill: true` also reports links that leave the skill's own folder,
  because an installed skill can be copied without the files around it.
- `pub-archive-includes-skill` checks that `dart pub publish` includes each
  skill and the files it links to. A path dependency ignores `.pubignore`, so
  testing that way doesn't catch a skill left out of the package.
- `published-skill-name` checks that each skill name is a valid name
  according to the [pub.dev `skills` package](https://pub.dev/packages/skills).
  Published package skills need such a name.

## 3. Add the test

Copy [validate_skills_example.dart](validate_skills_example.dart) to
`test/skills_lint_test.dart`. It loads `skills_lint.yaml` with
`ConfigParser.loadConfig()` and passes it to the `validateSkills` API.

`ConfigParser.loadConfig()` reads `skills_lint.yaml` from the current
directory, and `dart test` runs from the package root. The test fails if
`skills_lint.yaml` has an error or any skill has an error. Run the test with
`dart test test/skills_lint_test.dart`.

## 4. Fix what it reports

To fix findings, run the linter on its own with the same configuration:

```bash
dart run skills_lint
dart run skills_lint --fix
```

## 5. Ignore findings to fix later

If existing skills have too many findings to fix now, generate a baseline so
current errors are ignored:

```bash
dart run skills_lint --generate-baseline
```

Commit the generated ignore file. Ignored findings no longer fail the test,
while new findings still do.
