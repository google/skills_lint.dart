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

## 📦 Value Objects and Immutability

1. Annotate value model classes with `@immutable` (from `package:meta`).
2. **Do Not Override `operator ==`, `hashCode`, or `toString` Unless Required:** Unless a value class explicitly forms part of an equality-tested collection key or has a specific domain contract requiring structural equality, avoid overriding `operator ==`, `hashCode`, and `toString`. Unnecessary overrides increase maintenance overhead and cognitive complexity.

---

## 🛠 Message Construction & Helper Extraction

Extract multi-line strings, diagnostics, and formatted markdown message construction into focused private helper methods. Keeping string assembly separate from analysis routines prevents bloated `validate()` methods, ensures consistent diagnostic formatting, and makes rule logic straightforward to read and test.

---

## Tests

Tests give confidence that the code keeps working through refactors and added features, and that customers don't break. A failing test is often read only in CI logs, from an OS the author didn't run.

- Don't write tautological tests or change detectors. A test that restates the code, or breaks on every change, gives no confidence.
- A failing test's output must be enough to debug from CI logs alone. Name the input, the expected value and the actual value.
- Every `skip:` or `testOn:` gives the reason at that spot.
- "Hard to test" is not a reason to skip unit tests for pure logic. Pure logic is the cheapest code to test.

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
