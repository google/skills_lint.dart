# House style notes

The formatter decides layout. These rules are the ones it leaves to you.

## Names

- Use `lowerCamelCase` for variables, functions and constants.
- Use `UpperCamelCase` for types and extensions.
- Name a boolean for what it asserts, such as `isEmpty` or `hasErrors`.

## Comments

- Start doc comments with `///` and a one-sentence summary.
- Describe what the code does, not how it got that way.
- Put a reference to a parameter in square brackets, such as `[path]`.

## Imports

- Put `dart:` imports first, then `package:` imports, then relative imports.
- Leave one blank line between the groups.
