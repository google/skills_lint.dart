## 0.5.2

- Added programmatic YAML serialization support across configuration models, allowing configurations to be generated and formatted back into YAML.
- Added `ConfigParser.parse()` to support parsing configuration YAML directly from in-memory strings.
- Added the `published-skill-name` lint rule to validate that published skills in a Dart package's `skills/` directory follow the package naming convention required by `package:skills`.
- **Behavior change:** `directories`, `individual_skills`, and `ignore_file` paths now resolve relative to the configuration file that declares them rather than the current working directory. Configurations read from a different directory than the linter runs in must be rewritten: a `tool/skills_lint.yaml` invoked from the repository root needs `"../.agents/skills"` where it previously had `".agents/skills"`.
- Added `sourcePath` and `baseDirectory` parameters to `ConfigParser.parse()` to select the directory that in-memory configuration paths resolve against.
- Recorded `--generate-baseline` ignore entries with file names relative to the skill directory, naming the skill directory itself `.`, so a committed baseline matches on any machine and from any working directory. Entries written by earlier versions keep matching.
- Recorded the `path` and `ignore_file` text that each parsed configuration target was declared with, and emitted that text when serializing, so a configuration read from a file and written back keeps the paths its author wrote.
- Added `--format=sarif` and `--format=json` CLI options to emit validation results as standard OASIS SARIF 2.1.0 JSON documents or raw JSON arrays for CI and GitHub Code Scanning integration (#10).
- Attached the `skills_lint internal error:` prefix to operational failure notices on standard error (such as I/O errors, rename collisions, or baseline format errors) to distinguish tool execution errors from skill validation diagnostics.
- Fixed CLI usage output to correctly print to standard error when triggered by an argument parsing error, while `--help` continues to print to standard output.
- Fixed `--fix` for `absolute-paths` rule to preserve optional markdown link titles when rewriting absolute paths to relative paths.
- Fixed `name-format` and `published-skill-name` auto-fixing to safely handle empty or null frontmatter name fields without corrupting YAML delimiters or scalar spans.

## 0.5.1

- Migrated developer setup, integration recipes, and documentation to use `dart install skills@^1.0.0` and `dart install skills_lint`.
- Removed legacy npm-based tooling artifacts (`.npmrc` and `skills-lock.json`).

