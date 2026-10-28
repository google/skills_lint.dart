# Style & Conventions Guide: Agent Skills Linter (`skills_lint`)

This guide establishes the coding conventions, documentation standards, and style guidelines for the `skills_lint` codebase.

For system architecture and lifecycle documentation, see the [Architecture Overview](architecture_overview.md).

---

## 🎯 Effective Dart Compliance

All Dart code across this repository must adhere strictly to the official [Effective Dart Guidelines](https://dart.dev/effective-dart/):

1. **[Effective Dart: Style](https://dart.dev/effective-dart/style)**:
   - Identifiers: `UpperCamelCase` for types, `lowerCamelCase` for members/variables, `lowercase_with_underscores` for files and libraries.
   - Formatting: Always format code with standard `dart format`.
   - Ordering: Place `dart:` imports first, followed by `package:` imports, then relative imports. Sort alphabetically within sections.
   - Capitalize acronyms longer than two letters like words (`Uri`, `Json`, not `URI`, `JSON`).

2. **[Effective Dart: Documentation](https://dart.dev/effective-dart/documentation)**:
   - Use `///` for doc comments, not block comments.
   - **Avoid Tautological Comments:** Do not write comments that merely restate member names (e.g. avoid `/// The start line.` on `final int startLine;`).
   - **Document Contracts & Nullability (repo rule):** Document a public declaration when its contract isn't obvious from its name and type: coordinate systems (1-based vs 0-based), units, expected value ranges, side effects, and the precise meaning of `null` values. Don't add a doc comment only to have one; `public_member_api_docs` is off in this repo for that reason.
   - **Use Semantic Dartdoc Links:** Use square-bracketed symbol links (e.g. `[OutputFormat.text]`) rather than plain backticked strings (`\`text\``) for code entities.
   - **Summary sentence:** Follow Effective Dart on [noun-phrase docs](https://dart.dev/effective-dart/documentation#prefer-starting-a-non-boolean-variable-or-property-comment-with-a-noun-phrase) and the [single-sentence summary](https://dart.dev/effective-dart/documentation#do-start-doc-comments-with-a-single-sentence-summary). Put conditions and `null` cases in later paragraphs.
   - **Short summary (repo rule):** Keep the first sentence short enough that it rarely needs to wrap. The vendored [`dart-long-lines`](../../../../.agents/skills/dart-long-lines/SKILL.md) skill allows wrapping it, and that is fine when a shorter sentence would lose meaning.
   - **No leading "Returns" (repo rule):** Don't start the first sentence with "Returns". Effective Dart allows it; this repo doesn't. If the result matters most, give the function a noun name and describe the result with a noun phrase. If the operation matters most, start with a third-person verb ("Parses", "Writes"). A later paragraph may start with "Returns". [doc_comment_convention_test.dart](../../repo_test/doc_comment_convention_test.dart) enforces this.

     ```dart
     // Bad
     /// Returns the problems with the formula in [assets].
     String? get formulaProblems => ...;

     // Good
     /// Description of the problems with the formula in [assets].
     ///
     /// Is `null` if the formula has no problems, or if there is no formula.
     String? get formulaProblems => ...;
     ```

   - **Answer, don't ask (repo rule):** A doc comment contains no questions. Find out the answer before you write the doc.

3. **[Effective Dart: Usage](https://dart.dev/effective-dart/usage)** & **[Design](https://dart.dev/effective-dart/design)**:
   - Prefer `final` fields and immutable data structures.
   - Use pattern matching and switch expressions where appropriate.

---

## Temporal Words

Describe the code as it is. Don't compare it with an earlier version of the code, or with the change that produced it. This applies to code, comments and docs.

The reader has only the code in front of them. A comparison with a version they never saw doesn't help them, and it stops being true once that version is forgotten. For example:

- Instead of "the legacy `--fix-apply` alias", write "the deprecated `--fix-apply` alias".
- Instead of "the rule now explains the reason in its message", write "the rule explains the reason in its message".

Words such as "now", "still", "currently", "new", "old", "legacy", "existing behavior", "used to", "previously", "no longer" and "originally" often signal a comparison. Rewrite the sentence rather than swap the word. The same words are fine when they describe what the program does at runtime, as in "the directory no longer exists after the rename".

If you want to call something "new" or "legacy", pick a name that says what it is. If the history matters, put it in the commit message or PR description.

---

## Naming

Name things for what they are, not for what they are not. A name that describes what is missing only makes sense next to the thing it excludes.

---

## Readability

Write code a reviewer can follow in one pass.

Prefer a plain loop when a collection literal combines `for`, `if` and a null-aware `?` element. Keep collection-`for` for simple maps and filters.

The vendored [`dart-modern-features`](../../../../.agents/skills/dart-modern-features/SKILL.md) skill recommends null-aware elements. In this repo, this section wins.

Hard to follow:

```dart
return [
  for (final String key in parameters.params.keys)
    if (parameterConstraints.containsKey(key) && parameterSchema.containsKey(key))
      ?_validateValue(key, parameters.params[key]),
];
```

Easier:

```dart
final List<String> errors = [];
for (final String key in parameters.params.keys) {
  final bool isConstrained =
      parameterConstraints.containsKey(key) && parameterSchema.containsKey(key);
  if (!isConstrained) {
    continue;
  }
  final String? error = _validateValue(key, parameters.params[key]);
  if (error != null) {
    errors.add(error);
  }
}
return errors;
```

---

## Regular Expressions

Keep every piece of `RegExp` syntax in a raw string (`r'...'`). Regular expressions are hard to read already, and escapes in a non-raw string are easy to get wrong.

To include a value in a pattern, keep the regex syntax in raw strings. A non-raw piece contains only the interpolated value (`'$value'`). Join the pieces with `+` or with adjacent string literals. Wrap the value in `RegExp.escape` unless it is a constant with no regex syntax.

The [`use_raw_strings`](https://dart.dev/tools/linter-rules/use_raw_strings) lint doesn't catch interpolated strings, so this rule covers them.

Bad:

```dart
final RegExp line = RegExp('^([0-9a-f]{64})$separator(\\S+)\$');
```

Good:

```dart
// Matches a checksum line: a 64-character hex SHA-256 hash, the separator,
// then the file name.
final RegExp line = RegExp(r'^([0-9a-f]{64})' '$separator' r'(\S+)$');
```

---

## 🔑 Class Constants for Schema and Property Keys

All JSON schema property keys, serialization map keys, YAML frontmatter keys, and CLI option names must be declared as `static const String` constants co-located on their owning model classes (e.g., `keyRuleId`, `keyStartLine`, `keyName`).

```dart
class SourceRegion {
  static const String keyStartLine = 'startLine';
  static const String keyStartColumn = 'startColumn';
  static const String keyEndLine = 'endLine';
  static const String keyEndColumn = 'endColumn';
  // ...
}
```

**Rationale:** Centralizing keys prevents typo bugs, eliminates magic string duplication, and ensures downstream renames fail at compile time.

Group constants by concept (for example CLI flags, then messages). Separate each group with a blank line.

---

## 🧱 Parse at the Boundary & Make Illegal States Unrepresentable

Parse untyped external data (YAML, JSON, CLI arguments, filesystem paths) once where it enters the system into typed Dart classes, records, enums, or `File`/`Directory` objects. Do not pass raw `Map<String, dynamic>` option bags, boolean origin flags, or three or more positional `String` parameters across internal APIs, and do not re-parse strings that `package:yaml` already typed.

```dart
// BAD: Passing raw dynamic maps, re-parsing YAML booleans, or using boolean origin flags.
class RelativePathsRule extends SkillRule {
  RelativePathsRule({Map<String, dynamic>? options})
    : checkDirectories =
          options?['check-directories'] == true ||
          options?['check-directories'] == 'true';
  final bool checkDirectories;
}

// GOOD: Parse once at the config boundary; accept a typed parameter with its canonical default.
class RelativePathsRule extends SkillRule {
  RelativePathsRule({this.checkDirectories = defaultCheckDirectories});

  static const bool defaultCheckDirectories = false;
  final bool checkDirectories;
}
```

```dart
// BAD: Multiple positional String parameters and raw path strings passed into file utilities.
YamlEditResult buildSuppressionEdit(
  String content,
  String targetKey,
  String ruleId,
  String severity,
);
Future<List<String>> findUnformattedFiles(String rootDirPath);

// GOOD: Named parameters or a typed record/model, and `Directory`/`File` at the API boundary.
YamlEditResult buildSuppressionEdit(
  String content, {
  required String targetKey,
  required String ruleId,
  required String severity,
});
Future<List<File>> findUnformattedFiles(Directory rootDir);
```

---

## 🎯 Single Source of Truth (One Decision in One Place)

Every default parameter value, schema key, URI scheme allowlist, file extension set, or path-normalization helper lives in one canonical place. Callers and registries forward or reference that definition rather than repeating the literal.

```dart
// BAD: Repeating the default value (`false`) in both the rule registry and the rule constructor.
// In rule_registry.dart:
RelativePathsRule(
  checkDirectories: (options['check-directories'] as bool?) ?? false,
)

// GOOD: Reference the class constant from the owning rule.
RelativePathsRule(
  checkDirectories:
      options[RelativePathsRule.keyCheckDirectories] as bool? ??
      RelativePathsRule.defaultCheckDirectories,
)
```

---

## 📦 Value Objects and Immutability

1. Annotate value model classes with `@immutable` (from `package:meta`).
2. **Do Not Override `operator ==`, `hashCode`, or `toString` Unless Required:** Unless a value class explicitly forms part of an equality-tested collection key or has a specific domain contract requiring structural equality, avoid overriding `operator ==`, `hashCode`, and `toString`. Unnecessary overrides increase maintenance overhead and cognitive complexity.

---

## 🛠 Message Construction & Helper Extraction

Extract multi-line strings, diagnostics, and formatted markdown message construction into focused private helper methods. Keeping string assembly separate from analysis routines prevents bloated `validate()` methods, ensures consistent diagnostic formatting, and makes rule logic straightforward to read and test.

---

## 🔄 Refactoring & Addressing Review Feedback

When a requirement or review comment exposes that a helper, class, or test has mixed responsibilities, redesign the data flow rather than bolting a boolean toggle or extra conditional branch onto the existing signature.

```dart
// BAD: Bolting a boolean mode flag onto a checker when a test needs filesystem-walk vs git-tracked discovery.
Future<List<File>> findMissingCopyrightHeaders(
  Directory root, {
  bool useGitLsFiles = true,
});

// GOOD: Separate file discovery from header checking so callers pass the exact iterable of files they want checked.
Future<List<File>> findMissingCopyrightHeaders(Iterable<File> files);
```

---

## Tests

Tests give confidence that the code keeps working through refactors and added features, and that customers don't break. A failing test is often read only in CI logs, from an OS the author didn't run.

- Don't write tautological tests or change detectors. A test that restates the code, or breaks on every change, gives no confidence.
- A failing test's output must be enough to debug from CI logs alone. Name the input, the expected value and the actual value.
- Every `skip:` or `testOn:` gives the reason at that spot.
- "Hard to test" is not a reason to skip unit tests for pure logic. Pure logic is the cheapest code to test.
- **Verify the test fails first (Red-First):** For every bug fix or diagnostic rule check, confirm the test fails without the fix for the expected reason.
- **Test round-trip contracts on fixes and serializers:** Every test of an auto-fix (`SkillRule.fix`), YAML editor, or baseline/config generator feeds the modified output back through the parser or `Validator` and asserts that the target violation is resolved and no unintended diagnostics are introduced.
- **Isolate the rule under test in fixtures:** Minimal `SKILL.md` fixtures include valid required frontmatter (`name` and `description`) unless the test targets missing frontmatter, so unrelated rule failures cannot mask or mimic the diagnostic under test.
- Tests of the shipped skills_lint package go in `test/`. Scans that fail when the repo drifts go in `repo_test/`, and unit tests of their checker code go in `repo_test/checkers/`. See [Where tests go](../../../../CONTRIBUTING.md#where-tests-go).

---

## 🪟 Windows Compatibility

CI runs every test on Windows, macOS, and Linux.

- Build every path with `package:path` (`p.join`). Never hardcode `/` or `\`.
- In tests, build expected paths with `p.join`, or compare both sides after `p.normalize`. An expected path with hardcoded separators passes on macOS and Linux and fails on Windows.
- If a test depends on an OS-specific command (such as `chmod`), give a Windows equivalent (such as `icacls`) or mock the call.

---

## 📺 Standard Output & Error Hygiene

- **Stdout:** Reserved exclusively for standard human-readable lint reports (`--format=text`) and valid, parseable machine documents (`--format=json`, `--format=sarif`).
- **Stderr:** Reserved for operational failures, runtime error messages, usage help on bad arguments, and deprecation notices.
- All internal tool errors must be prefixed with `${Reporter.toolErrorPrefix}` (`skills_lint internal error:`).
