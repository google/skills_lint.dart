# Rules

The full rule contract for `skills_lint`. Every built-in rule listed
here is registered in
[`lib/src/rule_registry.dart`](lib/src/rule_registry.dart) and pinned to
this document by
[`repo_test/rules_md_consistency_test.dart`](repo_test/rules_md_consistency_test.dart).
If a rule is added, removed, renamed, or has its default severity /
fixability changed, both the registry **and** this file must be updated
in the same commit — the consistency test fails otherwise.

Severity vocabulary:

- `error` — failure exits 1 and blocks CI.
- `warning` — printed but does not change exit code.
- `disabled` — not run unless explicitly enabled via CLI flag or
  `skills_lint.yaml` `rules:` config.

All rules are enabled / disabled / escalated the same three ways:

- CLI: `--<rule-name>` (escalates to `error`),
  `--no-<rule-name>` (disables).
- YAML config: `skills_lint.rules.<rule-name>: error|warning|disabled`.
- Per-target YAML: `skills_lint.directories[].rules.<rule-name>: ...` or `skills_lint.individual_skills[].rules.<rule-name>: ...`.

The "Disable" line under each rule below names the negated CLI flag for
quick reference.

An entry in an ignore file covers every finding of one rule in one file.
A rule with an "Ignore subject" line names what each finding is about, and
an entry with that `subject` covers only the findings about it. The format
of a rule's subject is part of its contract.

See [`CONTRIBUTING.md`](../../CONTRIBUTING.md#rule-stability-policy-semver) for the SemVer policy that
governs how changes to these rules ship.

---

## check-absolute-paths

- **Default severity:** warning
- **Fixable:** yes
- **What it checks:** inline Markdown links in `SKILL.md` do not use
  absolute filesystem paths (POSIX `/foo/bar` or Windows `C:\foo`).
  Absolute paths break portability across machines.
- **Diagnostic shape:**
  `Absolute filepath found in link: <path>. Skills must use paths relative to SKILL.md so they remain portable across machines.`
- **Auto-fix behavior:** if the absolute path resolves to a file that
  exists on disk, the fixer rewrites it to the equivalent POSIX-style
  relative path from `SKILL.md`. If the target does not exist the
  fixer leaves the link untouched. If an ignore entry covers any of the
  links, the fixer leaves the file unchanged.
- **Ignore subject:** the link destination as written, including any
  `#anchor`, without its title.
- **Disable:** `--no-check-absolute-paths`.

## check-relative-paths

- **Default severity:** disabled
- **Fixable:** no
- **What it checks:** inline Markdown links in `SKILL.md` with
  relative targets resolve to files that actually exist on disk.
  Web URLs, anchors, `mailto:`, `javascript:`, and `data:` links are
  skipped. Percent escapes are decoded first, as on GitHub, so
  `my%20file.md` resolves to `my file.md` and `a%2Fb.md` to `a/b.md`.
  A link that does not decode to a relative path, such as `x%E9.md`
  or `%2Fetc%2Fpasswd`, or that decodes to one with a NUL, such as
  `a.md%00b`, is checked as written.
- **Diagnostic shape:**
  `Linked file does not exist: <path> (resolved to <absolute path>). Did you mean "<sibling>"?`
  The `Did you mean` clause is only included when a near-miss file
  is found in the same directory; it's scored by string similarity
  against the missing basename. The suggestion preserves the link's
  original directory prefix, normalized to forward slashes.
  With `within-skill: true`, a link outside the skill directory is
  reported as:
  `Linked file is outside the skill directory: <path> (resolved to <absolute path>). The link breaks when the skill is installed on its own. Link to an absolute URL, or copy the content into the skill directory.`
- **Parameters:**
  - `within-skill` (boolean): report relative links that resolve
    outside the skill directory, the directory that contains
    `SKILL.md`. Such a link gets only this diagnostic; whether its
    target exists is not checked. Defaults to `false`.
    **Turn it on for published skills**, such as the skills in a Dart
    package's `skills/` directory, if they must keep working once
    installed. However a skill is installed, it is copied somewhere
    else on its own, so such a link works in the author's repository
    but breaks once installed. Links into a
    sibling skill (`../other-skill/SKILL.md`) are reported too,
    because the consumer can install one skill without the other.
    The check uses the decoded path, so `%2E%2E%2FREADME.md` is
    reported like `../README.md`. Set it in `skills_lint.yaml`
    (`check-relative-paths: { severity: error, within-skill: true }`)
    or with `--check-relative-paths-within-skill=true`. The CLI flag
    takes precedence over the configuration file. To turn it on for
    published skills only, set it on their directory, as in
    [the README example](README.md#2-as-a-command-line-tool-with-a-yaml-configuration-file).
- **Auto-fix behavior:** none. The author is expected to pick the
  intended target by hand. For a link outside the skill directory,
  only the author can choose between an absolute URL and a copy of
  the content. `check-absolute-paths --fix` rewrites an absolute
  link to a file outside the skill as a `../` link, which
  `within-skill` then reports.
- **Ignore subject:** the link destination as written, including any
  `#anchor`, without its title.
- **Disable:** `--no-check-relative-paths` (also the default state).

## check-trailing-whitespace

- **Default severity:** disabled
- **Fixable:** yes
- **What it checks:** lines in `SKILL.md` do not have trailing
  whitespace. Exactly two spaces are allowed as a CommonMark hard
  line break; one space or three-or-more spaces, or any trailing tab,
  is reported. `\n`, `\r\n` and a lone `\r` all end a line, both
  for the check and for the fix.
- **Diagnostic shape:**
  `Line <N> has <count> trailing space(s). Only exactly 2 spaces are
  allowed for line breaks.`
  Trailing tabs report `Line <N> has trailing whitespace containing
  tabs.` instead.
- **Auto-fix behavior:** trims violating trailing whitespace from
  each offending line. Lines with exactly two trailing spaces are
  left alone.
- **Disable:** `--no-check-trailing-whitespace` (also the default
  state).

## description-too-long

- **Default severity:** error
- **Fixable:** no
- **What it checks:** the YAML frontmatter `description:` field is
  at most `max-length` characters (1024 by default, the
  Agent Skills specification limit).
- **Diagnostic shape:** at the default limit of 1024:
  `Description field is <N> characters; maximum is 1024. Cutoff:
  ...<40 chars before>|HERE|<40 chars after>... (see
  https://agentskills.io/specification#description-field)`
  The `|HERE|` marker sits at character `<limit>`, so the author can
  see what slipped past the limit without having to count characters.
- **Parameters:**
  - `max-length` (positive integer): maximum description
    length in characters. Defaults to `1024`. Set it in
    `skills_lint.yaml`
    (`description-too-long: { severity: error, max-length: 500 }`)
    or with `--description-too-long-max-length=500`. The CLI
    flag takes precedence over the configuration file. Zero, negative,
    and non-integer values are rejected.
- **Auto-fix behavior:** none. The fix is editorial; the linter
  refuses to silently truncate the author's prose.
- **Disable:** `--no-description-too-long`.

## disallowed-field

- **Default severity:** disabled
- **Fixable:** no
- **What it checks:** every key in the YAML frontmatter is one of the
  spec-allowed fields: `name`, `description`, `license`,
  `allowed-tools`, `metadata`, `compatibility`, `category`, `tags`,
  `version`, `eval_task`.
- **Diagnostic shape:**
  `Disallowed field: <key> (see
  https://agentskills.io/specification#frontmatter)`
- **Auto-fix behavior:** none. The fix is destructive (removing a
  field) so it requires a human decision.
- **Disable:** `--no-disallowed-field` (also the default state).

## prevent-skills-sh-publishing

- **Default severity:** disabled
- **Fixable:** no
- **What it checks:** the YAML frontmatter contains `metadata:` with `internal: true`, which prevents the skill from being published to skills.sh.
- **Diagnostic shape:**
  A multi-line message specifying the exact structural issue. It instructs the developer to remove quotes if `internal` is set to a string, or warns when `metadata` is missing, not a map, or when `internal` is not explicitly set to boolean `true`. Each diagnostic includes the expected schema:
  ```yaml
  metadata:
    internal: true
  ```
- **Auto-fix behavior:** none.
- **Disable:** `--no-prevent-skills-sh-publishing` (also the default state).

## invalid-skill-name

- **Default severity:** error
- **Fixable:** yes
- **What it checks:** the frontmatter `name:` field is:
  - lowercase
  - 1–64 characters
  - only lowercase letters, digits, and hyphens
  - has no leading, trailing, or consecutive hyphens
  - exactly equal to the parent directory's name

  The value counts as the text written, so `name: 1e3` is `1e3`,
  not the number `1000.0` that YAML reads.
- **Diagnostic shape:** each violation produces a separate error
  message naming the frontmatter `name:` field explicitly,
  quoting the offending value, and suggesting a normalized form
  (e.g. `Frontmatter `name` "My_Skill" contains invalid characters.
  Only lowercase letters, digits, and hyphens are allowed.
  Suggested: "my-skill" (see
  https://agentskills.io/specification#name-field)`).
  The directory-mismatch error offers both fix directions (edit the
  field or rename the directory).
- **Auto-fix behavior:** when the only violation is a directory
  mismatch and the directory name is itself a valid skill name, the
  fixer rewrites the frontmatter `name:` value to the directory name.
  It keeps the quotes the value already has, and double-quotes a name
  such as `123`, `true` or `null` that YAML would read as another
  type. For a directory name that is not a valid skill name, such as
  `my_skill` or `My Skill #1`, it leaves the file unchanged and the
  error is reported. Other violations (invalid characters, length,
  etc.) are not auto-fixed because the normalization is a suggestion
  and the author may want a different name entirely.
- **Disable:** `--no-invalid-skill-name`.

## pub-archive-includes-skill

- **Default severity:** disabled
- **Fixable:** no
- **What it checks:** for a skill in `skills/<name>/` of a Dart package,
  `dart pub publish` uploads `skills/<name>/SKILL.md` and every file in
  the package that `SKILL.md` links to, inside the skill or elsewhere in
  the package, such as `../../README.md`. A `.pubignore` or `.gitignore`
  pattern can drop a file from the published package with no warning, and
  a path dependency ignores `.pubignore`, so local testing doesn't show
  it. A link to a file outside the package is reported, because pub never
  publishes it. The package is the nearest directory above the skill
  with a `pubspec.yaml`. Skills outside its `skills/` directory pass without
  running `pub`. Links to files that don't
  exist pass too, even when `check-relative-paths` is disabled; enable
  `check-relative-paths` to report them.
- **How it works:** runs
  `dart pub publish --skip-validation --to-archive=<temp file>` once per
  package and reads the file names from the archive. Needs `dart` on
  `PATH`. `--to-archive` is a hidden pub option; if pub rejects it, the
  rule reports pub's error.
- **Diagnostic shape:**
  `` skills/<name>/SKILL.md is not in the package pub publishes, so the published package has no <name> skill. <fix> ``
  `` <file>, linked from skills/<name>/SKILL.md, is not in the package pub publishes. <fix> ``
  `` <file>, linked from skills/<name>/SKILL.md, is <archive file> in the package pub publishes. Match the file name case so the link works on case-sensitive file systems. ``
  `` <file>, linked from skills/<name>/SKILL.md, is outside the package, so pub does not publish it. Move the file into the package, or link to an absolute URL. ``
  `` <directory>/ is not in the package pub publishes, so neither are the <count> files skills/<name>/SKILL.md links to in it. <fix> ``
  where `<fix>` is
  `` Run `dart pub publish --dry-run` to list the files pub publishes, and check .pubignore and .gitignore. ``
  Missing files under a directory with no published files are reported
  once, as that directory. When the file list can't be built, each skill
  in `skills/` gets one diagnostic with the reason: `publish_to: none`,
  `dart` not found, or a pub failure. With no `pubspec.yaml` at all, every
  skill the rule runs on gets that diagnostic. The rule never passes a
  skill in `skills/` without the file list.
- **Auto-fix behavior:** none.
- **Disable:** `--no-pub-archive-includes-skill`.

## published-skill-name

- **Default severity:** disabled
- **Fixable:** yes
- **What it checks:** skills in a published Dart package's `skills/` directory follow the naming convention required by `package:skills`. The frontmatter `name:` must match the package name or start with the package name followed by a hyphen (e.g., `skills-lint` or `skills-lint-setup` for package `skills_lint`).
- **Diagnostic shape:**
  `Skill "<name>" does not follow the Dart package published skill naming convention for package "<package>". Published skills must start with "<hyphen-prefix>". Suggested name: "<suggestion>".`
  `Fix by re-running your validation command with --fix.`
  `(see https://pub.dev/packages/skills#naming-convention)`
- **Parameters:**
  - `package_name` (string): explicit Dart package name override.
  - `pubspec_path` (string): explicit path to `pubspec.yaml` (absolute path, or relative to the CLI invocation working directory `Directory.current`). When omitted, `pubspec.yaml` is auto-discovered by walking up parent directories starting from the skill directory.
- **Auto-fix behavior:** updates the frontmatter `name:` in `SKILL.md` to the suggested normalized package skill name and automatically aligns the parent directory name on disk when run via `--fix`.
- **Related:** published skills are installed one at a time, so
  links out of the skill directory break. Turn on
  [`check-relative-paths`](#check-relative-paths) with
  `within-skill: true` for the same directory.
- **Disable:** `--no-published-skill-name` (also the default state).

## unknown-rule-name

- **Default severity:** disabled
- **Fixable:** no
- **What it checks:** every rule name in `skills_lint.yaml` is a rule
  that skills_lint knows about: a built-in rule, or a custom rule passed
  to `validateSkills(customRules: ...)`. It looks at the top-level
  `rules` and at the `rules` of each `directories` and
  `individual_skills` entry. It checks the configuration once per run,
  so only the top-level `rules` and the command line can turn it on.
  The `skills_lint` command doesn't know about custom rules, so if you
  turn this rule on there, add your custom rule names to `allow`.
- **Diagnostic shape:**
  `Global rules: Unknown rule "<name>". Did you mean "<rule>"?`
  For an entry, `Global rules` becomes `Directory entry rules for
  "<path>"` or `Individual skill entry rules for "<path>"`. If the name
  is close to a name skills_lint knows about, including custom rules, it
  offers a suggestion. If two names are equally close, it offers none.
- **Parameters:**
  - `allow` (list of strings): names to accept anyway, such as a rule
    that only a newer skills_lint has. Ignore files can't do this,
    because they match findings in a skill's files.
- **Auto-fix behavior:** none.
- **Disable:** `--no-unknown-rule-name` (also the default state).

## valid-yaml-metadata

- **Default severity:** error
- **Fixable:** no
- **What it checks:**
  - `SKILL.md` contains a YAML frontmatter block delimited by `---`
    that parses without errors.
  - Required fields `name` and `description` are both present.
  - If `compatibility:` is present, it is at most 500 characters.
- **Diagnostic shape:**
  - `Invalid YAML metadata: <parser error> (see
    https://agentskills.io/specification#frontmatter)`
  - `Missing required field: <field> (see ...)`
  - `Compatibility field is <N> characters; maximum is 500. Cutoff: ...<context>|HERE|<context>... (see https://agentskills.io/specification#compatibility-field)`
    — same shape as `description-too-long`, produced by the shared
    `buildLengthDiagnostic` helper.
- **Auto-fix behavior:** none. A broken frontmatter block isn't
  safely mechanically repairable.
- **Disable:** `--no-valid-yaml-metadata`.

## path-does-not-exist

- **Default severity:** error
- **Fixable:** no
- **What it checks:** the skill directory exists, is actually a directory, and contains a `SKILL.md` file.
- **Diagnostic shape:**
  `SKILL.md is missing in directory: <dir> (see https://agentskills.io/specification#directory-structure)`
- **Auto-fix behavior:** none.
- **Disable:** `--no-path-does-not-exist`.

