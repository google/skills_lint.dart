# User-Facing Changes

Use this guide for any change a user can see:

- text or SARIF output
- `--help` text
- config keys
- error messages

## Steps

1. Draft the real before/after output.
2. Show it to the maintainer before you write code.
3. Paste the approved examples into the PR description.

Agreeing on the output first is cheaper than reworking the code after review.

## Examples

- [#43](https://github.com/google/skills_lint.dart/pull/43) added a length limit parameter.
  Most review comments were about naming and output, not logic. For example, the parameter
  type ([C1](https://github.com/google/skills_lint.dart/pull/43#discussion_r4124089227)) and
  the key style ([C12](https://github.com/google/skills_lint.dart/pull/43#discussion_r4124386302)).
  A before/after draft would have raised these before any code existed.
- [#44](https://github.com/google/skills_lint.dart/pull/44) changed the diagnostic shown when
  a configured target is missing. The message text is the product, so draft it and get it
  approved first.
