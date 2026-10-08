## 0.5.3-wip

- Requires Dart 3.12 or later.
- Added `ConfigSource.file` and `ConfigSource.directory` for `ConfigParser.parse()` and `ConfigParser.fromYaml()`. The `sourcePath` and `baseDirectory` arguments remain available but are deprecated.
- Added a `max-length` parameter to the `description-too-long` rule to configure the maximum description length. Set it in `skills_lint.yaml` (`description-too-long: { max-length: 500 }`) or with the `--description-too-long-max-length=500` CLI flag.
- When a path listed under `directories` or `individual_skills` in your configuration file does not exist, the error shows the path as you wrote it, the file and line where you wrote it, and the directory it was resolved from.
- **Behavior change:** in `--format=sarif` and `--format=json` output, the error for a missing `directories` or `individual_skills` path points at the line of the configuration file that lists it, instead of at the missing directory.
- **Behavior change:** `check-relative-paths` no longer offers a "Did you mean" file when two files are equally close to a broken link.
- Made `check-trailing-whitespace` about 20 times faster. Its diagnostics and `--fix` output are unchanged, except for the lone carriage return change below.
- Fixed `invalid-skill-name` `--fix` writing a directory name that YAML misreads, and then renaming the directory to the misread name: `My Skill #1` became `My Skill`, and `0x1f` became `31`. A name such as `0x1f` is written in quotes.
- **Behavior change:** `invalid-skill-name` `--fix` writes only a directory name that is a valid skill name. For a directory such as `my_skill`, it leaves `name` unchanged and reports the mismatch.
- **Behavior change:** `check-trailing-whitespace` treats a lone carriage return (`\r`) as a line break. It reports trailing whitespace before one, and running `--fix` twice gives the same result as running it once.
- **Behavior change:** `check-relative-paths` decodes percent escapes before it looks for the file, so `[doc](my%20file.md)` resolves to `my file.md`. A file named literally `my%20file.md` no longer matches it.
- **Behavior change:** after a custom rule's fixer changes `name`, `--fix` renames the skill directory, and `--fix --dry-run` proposes the rename, only to a valid skill name that YAML reads as a string. It does not rename to `my_skill` or to an unquoted `123`.
- Added a `--version` flag that prints the skills_lint version.

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

