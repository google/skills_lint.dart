---
name: triage-github-issues
description: Sorts new GitHub issues by type and priority, asks for missing details, and closes duplicates. Use when asked to triage, label or clean up the issue tracker.
license: Apache-2.0
metadata:
  internal: true
---

# Triage GitHub issues

Use this skill to work through issues that have no labels yet. The goal is
that every open issue has a type, a priority, and enough detail for someone
to start on it.

## Before you start

- Run [list-open-issues.sh](scripts/list-open-issues.sh) to get the issues
  that have no labels, oldest first.
- Read [labels.md](references/labels.md) for what each label means. Don't
  invent new labels.

```bash
scripts/list-open-issues.sh google/skills_lint.dart > /tmp/untriaged.json
```

## For each issue

1. Read the title, the body and every comment.
2. Search for duplicates with two or three key words from the title. If you
   find one, comment with a link to it, add `duplicate`, and close the issue.
3. Pick one type label: `bug`, `enhancement`, `documentation` or `question`.
4. Pick one priority label. Use `P1` only for a crash, data loss or a broken
   release. Most issues are `P2` or `P3`.
5. If you can't reproduce a bug from what the reporter wrote, ask for what is
   missing. Use the reply in [reply-templates.md](references/reply-templates.md),
   and add `needs-info`.

## Reproducing a bug

- Use the version the reporter used. If they didn't say, ask.
- Copy their command exactly, including flags and the working directory.
- Write down what you ran and what happened, in a comment on the issue, even
  when you can't reproduce it. The next person saves the time.

```bash
dart pub global activate skills_lint 0.5.2
skills_lint --skills-directory .agents/skills --format json
```

## Closing issues

- Close an issue with `needs-info` after 30 days with no reply. Say why in a
  comment, and say that the reporter can reopen it.
- Don't close an issue because it is old. Close it because it is fixed, a
  duplicate, or not going to be done, and say which.

## When you're done

Post a short summary in the team channel: how many issues you triaged, how
many you closed, and any `P1` you found.
