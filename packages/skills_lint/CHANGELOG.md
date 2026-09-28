## 0.5.3-wip

- Internal errors propagate instead of being hidden by catch-all handlers. Expected failures (malformed YAML, unreadable files, invalid command-line flags, a missing `git`) are handled as before. An unexpected `Error` while loading configuration, reading `SKILL.md`, parsing frontmatter, or renaming and saving files stops the run with a stack trace instead of being reported as a parse failure. The `unexpected-error` diagnostic (`Validator.unexpectedError`) is not emitted, because reading `SKILL.md` can only fail with a `FileSystemException`, which is reported as `skill-file-inaccessible`.
- Added a `max-length` parameter to the `description-too-long` rule to configure the maximum description length. Set it in `skills_lint.yaml` (`description-too-long: { max-length: 500 }`) or with the `--description-too-long-max-length=500` CLI flag.
- When a path listed under `directories` or `individual_skills` in your configuration file does not exist, the error shows the path as you wrote it, the file and line where you wrote it, and the directory it was resolved from.
- **Behavior change:** in `--format=sarif` and `--format=json` output, the error for a missing `directories` or `individual_skills` path points at the line of the configuration file that lists it, instead of at the missing directory.
- **Behavior change:** `check-relative-paths` no longer offers a "Did you mean" file when two files are equally close to a broken link.

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
- Exported `MissingDefaultsException`, which `validateSkills` already threw when no skill directories, individual skill paths, or configuration targets were supplied and no default location existed. Callers can now catch it by name instead of inspecting `runtimeType`.

## 0.5.1

- Migrated developer setup, integration recipes, and documentation to use `dart install skills@^1.0.0` and `dart install skills_lint`.
- Removed legacy npm-based tooling artifacts (`.npmrc` and `skills-lock.json`).

