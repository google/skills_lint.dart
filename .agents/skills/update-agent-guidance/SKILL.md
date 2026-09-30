---
name: update-agent-guidance
description: Rules for writing guidance that agents read. Use when you add or edit a SKILL.md, evals.json or AGENTS.md file in this repository.
metadata:
  internal: true
---

# Update Agent Guidance

Agents follow guidance literally, and it outlives the change that prompted it. Write it so that it stays true as the code changes.

## Rules

- Don't name specific tests, pull requests, review threads or people.
- State the principle, not the incident that taught it.
- Don't give exact thresholds that a test enforces. Agents aim for one below the limit. Link to the test, or describe the goal.
- Link to the one place a rule is defined. Don't copy it.
- Use markdown links for repo paths, so skills_lint fails when a file moves.
- Only add guidance you have seen needed more than once. Put unproven patterns in an issue.

## Evals

- Add an eval expectation for an instruction that would really hurt if it regressed. Not every change needs one, because evals are expensive to run. To choose between extending an eval and adding one, follow [Minimal & Orthogonal Evaluations](../../../packages/skills_lint/evals/README.md#minimal--orthogonal-evaluations).
