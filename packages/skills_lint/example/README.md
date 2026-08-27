# skills_lint examples

This directory contains examples of using `skills_lint` both programmatically as a Dart library and via the CLI.

## 1. Dart Library API Example

To see programmatic validation in action, run:

```bash
dart run example/main.dart
```

This demonstrates:
- **`validateSkills`**: Running high-level validation across skills or directories.
- **`Validator`**: Instantiating custom rule configurations and inspecting structured `ValidationResult` and `ValidationError` objects.

---

## 2. CLI Examples with Reference Fixtures

Two reference skill fixtures live in `example/skills/`:

| Fixture | Expected outcome |
| --- | --- |
| [`valid/`](skills/valid/SKILL.md) | All rules pass; the CLI exits 0. |
| [`invalid/`](skills/invalid/SKILL.md) | Multiple rules fail; the CLI exits 1. |

### Run the valid fixture

```bash
dart run skills_lint --skill ./example/skills/valid
```

Output:
```
Evaluating directory: example/skills/valid
--- Validating skill: valid ---
  Skill is valid.
```
Exit code: `0`.

### Run the invalid fixture

With default rule severities, only `invalid-skill-name` fires (the other two violations are below their default threshold):

```bash
dart run skills_lint --skill ./example/skills/invalid
```

Exit code: `1`. To see every violation surface as an error, escalate the other two rules with explicit flags:

```bash
dart run skills_lint --skill ./example/skills/invalid \
  --disallowed-field --check-absolute-paths
```

Three rules now report failures:
- `invalid-skill-name` — names the offending frontmatter value, calls out the directory mismatch, and suggests a corrected form.
- `disallowed-field` — names the unknown field (`secret_field`) and links to the spec's allowed-field list.
- `check-absolute-paths` — flags the `/tmp/...` link as non-portable and links to the spec section on relative paths.

### Trying out `--fix`

The invalid fixture's `check-absolute-paths` violation is auto-fixable when the target file exists. To experiment, point it at a real local file:

```bash
dart run skills_lint --skill ./example/skills/invalid --fix --dry-run
```

`--dry-run` shows the proposed diff without writing; omit `--dry-run` to apply the change to disk.
