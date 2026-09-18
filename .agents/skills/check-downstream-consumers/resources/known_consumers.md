# Known Downstream Consumers of `skills_lint`

When evaluating the impact of pull requests on downstream repositories, check against these known ecosystem consumers.

> [!NOTE]
> Local directory paths across individual development machines vary. Avoid assuming fixed directory locations. Locate repositories dynamically (e.g., searching relative to workspace root parent directories or checking common checkout folders) or consult machine-specific local Knowledge Items if available.

> [!TIP]
> Each entry links the file that actually invokes the linter. Read that file rather than trusting a description of it: it records the working directory, the flags, and the configuration file in use, all of which decide whether a change affects this consumer. The links use `blob/HEAD`, so they follow the default branch and return 404 once a file moves rather than silently pointing at stale content.

## Repository Directory & Usage Profile

### 1. `flutter/flutter`
- **Repository URL**: [flutter/flutter](https://github.com/flutter/flutter)
- **Primary Consumer Location**: `dev/tools/`
- **Tooling Engine**: `flutter pub get` and `flutter test`
- **Validation Entry Point**: [`dev/tools/test/validate_skills_test.dart`](https://github.com/flutter/flutter/blob/HEAD/dev/tools/test/validate_skills_test.dart)

### 2. `flutter/devtools`
- **Repository URL**: [flutter/devtools](https://github.com/flutter/devtools)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `flutter pub get` and `flutter test` (or `dart test`)
- **Validation Entry Point**: [`tool/test/validate_skills_test.dart`](https://github.com/flutter/devtools/blob/HEAD/tool/test/validate_skills_test.dart), also invoked from [`.agents/scripts/validate_skills_hook.sh`](https://github.com/flutter/devtools/blob/HEAD/.agents/scripts/validate_skills_hook.sh)

### 3. `flutter/packages`
- **Repository URL**: [flutter/packages](https://github.com/flutter/packages)
- **Primary Consumer Location**: Package-specific automation tools (for instance, `packages/camera/camera_android_camerax/pubspec.yaml` or shared verification test benches).
- **Tooling Engine**: `flutter pub get` and `flutter test`
- **Validation Entry Point**: [`packages/camera/camera_android_camerax/test/validate_skills_test.dart`](https://github.com/flutter/packages/blob/HEAD/packages/camera/camera_android_camerax/test/validate_skills_test.dart)

### 4. `dart-lang/site-www`
- **Repository URL**: [dart-lang/site-www](https://github.com/dart-lang/site-www)
- **Primary Consumer Location**: `site/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Validation Entry Point**: [`site/test/lint_skills_test.dart`](https://github.com/dart-lang/site-www/blob/HEAD/site/test/lint_skills_test.dart)

### 5. `dart-lang/skills`
- **Repository URL**: [dart-lang/skills](https://github.com/dart-lang/skills)
- **Primary Consumer Location**: `repo_tool/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Validation Entry Point**: [`repo_tool/test/lint_skills_test.dart`](https://github.com/dart-lang/skills/blob/HEAD/repo_tool/test/lint_skills_test.dart)

### 6. `kevmoo/dash_skills`
- **Repository URL**: [kevmoo/dash_skills](https://github.com/kevmoo/dash_skills)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Validation Entry Point**: [`tool/test/validate_skills_test.dart`](https://github.com/kevmoo/dash_skills/blob/HEAD/tool/test/validate_skills_test.dart)

### 7. `flutter/dash-evals`
- **Repository URL**: [flutter/dash-evals](https://github.com/flutter/dash-evals)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Validation Entry Point**: [`.github/workflows/lint_skills.yml`](https://github.com/flutter/dash-evals/blob/HEAD/.github/workflows/lint_skills.yml). This repository is access restricted, so the link returns 404 unless you are signed in with access. A 404 here does not imply the file moved.

### 8. `flutter/flutter-intellij`
- **Repository URL**: [flutter/flutter-intellij](https://github.com/flutter/flutter-intellij)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Validation Entry Point**: [`tool/validate_skills.sh`](https://github.com/flutter/flutter-intellij/blob/HEAD/tool/validate_skills.sh)

### 9. `flutter/dart-intellij-third-party`
- **Repository URL**: [flutter/dart-intellij-third-party](https://github.com/flutter/dart-intellij-third-party)
- **Primary Consumer Location**: `tool/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Validation Entry Point**: [`tool/validate_skills.sh`](https://github.com/flutter/dart-intellij-third-party/blob/HEAD/tool/validate_skills.sh)

### 10. `flutter/agent-plugins`
- **Repository URL**: [flutter/agent-plugins](https://github.com/flutter/agent-plugins)
- **Primary Consumer Location**: `tool/generator/`
- **Tooling Engine**: `dart pub get` and `dart test`
- **Validation Entry Point**: [`tool/generator/test/lint_skills_test.dart`](https://github.com/flutter/agent-plugins/blob/HEAD/tool/generator/test/lint_skills_test.dart)
