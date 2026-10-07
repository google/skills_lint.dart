---
name: contributor-pr-description
description: Guidelines and format for writing pull request descriptions in this repository. Use this skill whenever the user asks you to draft a pull request description, submit a PR, or update a PR description.
metadata:
  internal: true
---

# Pull Request Description Guidelines

When writing a pull request (PR) description, your goal is to provide reviewers with enough context to understand what you did, why you did it, and how they can verify it. A good PR description speeds up the review process and serves as documentation for future contributors.

## Identity Verification

If you are in an environment where there are multiple GitHub identities (e.g., an AI agent identity and a primary user identity), **you must verify your identity before pushing or creating a PR**.

Before committing, pushing, or opening a PR, ensure you are using the identity that the user expects based on the type of work and the repository you are working on. Verify your active GitHub CLI auth (`gh auth status`) and ensure your Git commit author (`git commit --author="..."`) matches the correct identity for the task.

## PR Description Template

Always use the following template (or a very similar structure) when drafting a PR description:

```markdown
## Summary
[Provide a clear, 1-2 sentence summary of what this PR does.]

## Motivation and Context
[Explain why this change is necessary. What problem does it solve? If it's a bug fix, what was the broken behavior?]

## Related Issues
[If this PR fixes an open issue, link to it using keywords. e.g., "Fixes #123" or "Closes #456". If it relates to an issue but doesn't close it, use "Related to #789".]

## What changed
[Optional: Provide a bulleted list of the most important technical changes made in the code. This is useful for larger PRs.]
- Added `FooClass` to handle XYZ.
- Updated `BarMethod` to return `Result`.

## API surface
[Omit if the PR changes nothing that users or callers see. See "API surface" below.]

## Testing Instructions
[Explain how reviewers can test your changes locally. Mention any manual verification steps.]
- Run `dart test` to ensure all tests pass.
- [Any specific manual testing steps]

```

## API surface

Names and output are hard to change once users depend on them, so get them reviewed first.

- List every public type, parameter, CLI flag and config key the PR adds or changes, with its constraints (for example, "must be a positive integer").
- For anything users see (CLI output, SARIF or JSON, `--help`, config keys), paste real before and after output from a run. Don't write it by hand.
- Show this to the reviewer and get approval before you write the code.

## Tone and Style

1. **Be clear and concise**: Avoid rambling. Use bullet points for readability.
2. **Focus on the "Why"**: The diff shows *what* changed. The description should explain *why* it changed.
3. **Be professional**: Use natural, accessible language.
4. **Explain scope**: Explain every change outside the PR's primary scope. Some changes should be pulled out into a separate PR.

## Examples of Bad vs Good Summaries

**Bad**: "Fixed the bug." (Too vague, doesn't explain what bug)
**Bad**: "Changed line 42 in `main.dart` to use `foo` instead of `bar`." (Focuses too much on the code, which is visible in the diff)

**Good**: "Fixes a crash when the user clicks 'Submit' without entering an email address by adding validation to the input form." (Explains the problem and the solution)
