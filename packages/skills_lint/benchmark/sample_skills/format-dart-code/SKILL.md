---
name: format-dart-code
description: Formats Dart code with dart format and fixes the lints that formatting can't. Use when a change fails the formatting check in CI.
metadata:
  internal: true
---

# Format Dart code

Use this skill when the formatting check fails, or before you send a change
for review.

## Steps

1. From the package root, run `dart format .`.
2. Run `dart analyze --fatal-infos`. Fix each issue that formatting can't
   fix, such as a line over 80 columns inside a string.
3. Run `dart format --output=none --set-exit-if-changed .` and confirm that
   it exits with 0.

```bash
dart format .
dart analyze --fatal-infos
```

## When formatting fights you

- A trailing comma after the last argument makes the formatter put each
  argument on its own line. Remove it to get one line.
- A `//` comment at the end of a list line stops the formatter from joining
  the list onto fewer lines.

See [style-notes.md](references/style-notes.md) for the house style that the
formatter doesn't enforce.
