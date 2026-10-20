# Dart test setup

Use this path for a Dart package, especially one that publishes skills in a
top-level `skills/` directory. `dart test` then fails when a skill is invalid.

## 1. Add the dependencies

From the package root:

```bash
dart pub add dev:skills_lint dev:test
```

Skip `dev:test` if `pubspec.yaml` already lists `test`.

## 2. Create skills_lint.yaml

Create `skills_lint.yaml` at the package root, next to `pubspec.yaml`:

```yaml
skills_lint:
  directories:
    - path: "skills"
      rules:
        published-skill-name: error
        check-relative-paths: error
```

- `published-skill-name` checks that each skill name is the package name with
  `_` replaced by `-`, or starts with it followed by `-`. For package
  `my_pkg`, that's `my-pkg` or `my-pkg-<anything>`. Published package skills
  need this name.
- `check-relative-paths` checks that every relative link resolves.

Change `skills` if the skills live somewhere else.

## 3. Add the test

Create `test/skills_lint_test.dart`. It calls the `validateSkills` API
directly, with the configuration from `skills_lint.yaml`:

```dart
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  test('skills pass skills_lint', () async {
    final Configuration config = await ConfigParser.loadConfig();
    expect(
      config.directoryConfigs,
      isNotEmpty,
      reason: 'skills_lint.yaml must list at least one skills directory.',
    );

    final bool passed = await validateSkills(config: config);

    expect(passed, isTrue, reason: 'skills_lint found errors. Its findings are printed above.');
  });
}
```

`ConfigParser.loadConfig()` reads `skills_lint.yaml` from the current
directory, and `dart test` runs from the package root. `validateSkills` prints
each finding and returns `false` if any skill has an error. Run the test with
`dart test test/skills_lint_test.dart`.

## 4. Fix what it reports

To fix findings, run the linter on its own with the same configuration:

```bash
dart run skills_lint
dart run skills_lint --fix
```
