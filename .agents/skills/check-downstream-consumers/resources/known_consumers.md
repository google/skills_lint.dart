# Known Downstream Consumers of `skills_lint`

When evaluating the impact of pull requests on downstream repositories, check against these known ecosystem consumers. 

> [!NOTE]
> Local directory paths across individual development machines vary. Avoid assuming fixed directory locations. Locate repositories dynamically (e.g., searching relative to workspace root parent directories or checking common checkout folders) or consult machine-specific local Knowledge Items if available.

## Repository Directory & Usage Profile

### 1. `flutter/flutter`
- **Repository URL**: [flutter/flutter](https://github.com/flutter/flutter)
- **Primary Consumer Location**: `dev/tools/`
- **Tooling Engine**: `flutter pub get` and `flutter test`
- **Focus Areas**: Validating agent skills embedded within repository automation and development workflows.

### 2. `flutter/devtools`
- **Repository URL**: [flutter/devtools](https://github.com/flutter/devtools)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `flutter pub get` and `flutter test` (or `dart test`)
- **Focus Areas**: Custom verification harnesses requiring absolute path isolation patterns (e.g., `validate_skills_test.dart`).

### 3. `flutter/packages`
- **Repository URL**: [flutter/packages](https://github.com/flutter/packages)
- **Primary Consumer Location**: Package-specific automation tools (for instance, `packages/camera/camera_android_camerax/pubspec.yaml` or shared verification test benches).
- **Tooling Engine**: `flutter pub get` and `flutter test`
- **Focus Areas**: Custom domain-specific validation rules extending `SkillRule` directly.

### 4. `dart-lang/site-www`
- **Repository URL**: [dart-lang/site-www](https://github.com/dart-lang/site-www)
- **Primary Consumer Location**: `site/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Focus Areas**: Web documentation generation workflows (`test/lint_skills_test.dart`).

### 5. `dart-lang/skills`
- **Repository URL**: [dart-lang/skills](https://github.com/dart-lang/skills)
- **Primary Consumer Location**: Root skill sets or tooling harnesses.
- **Tooling Engine**: `dart pub get` and `dart test`

### 6. `kevmoo/dash_skills`
- **Repository URL**: [kevmoo/dash_skills](https://github.com/kevmoo/dash_skills)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `dart pub get` and `dart test`


### 7. `flutter/dash-evals`
- **Repository URL**: [flutter/dash-evals](https://github.com/flutter/dash-evals)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Focus Areas**: Agent skill evaluation benchmarks and prompt validation harnesses.
- **Invocation**: `.github/workflows/lint_skills.yml` runs from `tool/` and passes
  `--skills-directory ../.agents/skills` explicitly. The repository-root
  `skills_lint.yaml` is therefore not what selects the scan targets.

### 8. `flutter/flutter-intellij`
- **Repository URL**: [flutter/flutter-intellij](https://github.com/flutter/flutter-intellij)
- **Primary Consumer Location**: `tool/` (config and script), with the
  `skills_lint` dependency declared in the **repository root** `pubspec.yaml`.
- **Tooling Engine**: `dart pub get` and `tool/validate_skills.sh`
- **Focus Areas**: Skill validation for the IntelliJ Flutter plugin, driven by
  `tool/grind.dart`.
- **Invocation**: `tool/validate_skills.sh` changes directory to the
  **repository root**, then runs
  `dart run skills_lint --config tool/skills_lint.yaml`.

> [!WARNING]
> **Highest-risk layout in the ecosystem.** This is the only known consumer
> whose working directory differs from the directory holding its configuration
> file. `tool/skills_lint.yaml` declares `directories: - path: ".agents/skills"`,
> a path that is only correct when resolved against the repository root.
> Any change to how configuration paths are anchored will silently retarget
> this repository's scan. Always test this consumer explicitly when touching
> path resolution; a passing exit code elsewhere proves nothing about it.

### 9. `flutter/dart-intellij-third-party`
- **Repository URL**: [flutter/dart-intellij-third-party](https://github.com/flutter/dart-intellij-third-party)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `dart pub get` and `tool/validate_skills.sh`
- **Focus Areas**: Skill validation for third-party Dart IntelliJ tooling.
- **Invocation**: `tool/validate_skills.sh` changes directory into `tool/` and
  runs `dart run skills_lint` with no `--config` flag, relying on discovery of
  `tool/skills_lint.yaml`. That config declares
  `directories: - path: "../.agents/skills"`, which resolves to the same
  directory whether anchored to the working directory or to the config file.
  Config and working directory are co-located, so this repository is **not**
  exposed to path-anchoring changes.

### 10. `flutter/flutter-skills`
- **Repository URL**: [flutter/flutter-skills](https://github.com/flutter/flutter-skills)
- **Primary Consumer Location**: `tool/generator/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Focus Areas**: Skill generation tooling; validates the largest known skill
  set of any consumer.

---

## Path-anchoring exposure at a glance

Configuration path resolution is the single most consumer-sensitive behavior in
this package, because a mis-anchored path produces an empty scan rather than an
error at the call site. Use this table before changing anything in
`path_utils.dart`, `config_parser.dart`, or `validation_session.dart`.

| Consumer | Config location | Working directory when run | Exposed? |
| :- | :- | :- | :- |
| `flutter/flutter-intellij` | `tool/` | repository root | **Yes** |
| `flutter/dash-evals` | repository root | `tool/` | No — uses `--skills-directory` |
| All other known consumers | co-located with working directory | same directory | No |

