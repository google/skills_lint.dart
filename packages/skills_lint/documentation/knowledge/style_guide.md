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
   - Use `///` doc comments for all public declarations.
   - **Avoid Tautological Comments:** Do not write comments that merely restate member names (e.g. avoid `/// The start line.` on `final int startLine;`).
   - **Document Contracts & Nullability:** Clearly document coordinate systems (1-based vs 0-based), units, expected value ranges, and the precise meaning of `null` values.
   - **Use Semantic Dartdoc Links:** Use square-bracketed symbol links (e.g. `[OutputFormat.text]`) rather than plain backticked strings (`\`text\``) for code entities.

3. **[Effective Dart: Usage](https://dart.dev/effective-dart/usage)** & **[Design](https://dart.dev/effective-dart/design)**:
   - Prefer `final` fields and immutable data structures.
   - Use pattern matching and switch expressions where appropriate.

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

---

## 📦 Value Objects and Immutability

1. Annotate value model classes with `@immutable` (from `package:meta`).
2. **Do Not Override `operator ==`, `hashCode`, or `toString` Unless Required:** Unless a value class explicitly forms part of an equality-tested collection key or has a specific domain contract requiring structural equality, avoid overriding `operator ==`, `hashCode`, and `toString`. Unnecessary overrides increase maintenance overhead and cognitive complexity.

---

## 🔗 Specification Link Integrity

**Never Invent or Speculate Specification URLs:**
Diagnostic messages and markdown help must only cite external URLs (such as `https://agentskills.io/specification`) if the rule directly validates a constraint explicitly mandated by that specification (such as required metadata fields or valid skill names).

Rules enforcing repository conventions, internal heuristics, or opt-in policies (such as `absolute-paths`) must never invent or attach speculative specification URLs.

---

## 🛠 Diagnostic Helper Builders

When authoring validation rules with complex or multi-line diagnostics (including GitHub Flavored Markdown messages), extract the construction into private helper builder methods (`_build...Error`):

```dart
ValidationError _buildDirectoryMismatchError({
  required String fieldName,
  required String dirName,
  required SourceRegion? region,
}) {
  return ValidationError(
    ruleId: name,
    severity: severity,
    file: _skillFileName,
    message: 'Skill name "$fieldName" does not match directory name "$dirName".',
    markdownMessage: '**Skill name mismatch.**

'
        'Frontmatter name: `$fieldName`
'
        'Directory name: `$dirName`

'
        '**How to fix:**
'
        'Update `name:` to match the directory, or rename the directory.',
    region: region,
  );
}
```

---

## 📺 Standard Output & Error Hygiene

- **Stdout:** Reserved exclusively for standard human-readable lint reports (`--format=text`) and valid, parseable machine documents (`--format=json`, `--format=sarif`).
- **Stderr:** Reserved for operational failures, runtime error messages, usage help on bad arguments, and deprecation notices.
- All internal tool errors must be prefixed with `${Reporter.toolErrorPrefix}` (`skills_lint internal error:`).
