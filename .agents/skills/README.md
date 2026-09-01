# Skills Lint

This directory (`packages/skills_lint/.agents/skills/`) contains skills and configurations for agents working on the `skills_lint` package.

All skills in this directory are available immediately without running an installation or fetch step:
* **Internal Skills:** Skills specific to `skills_lint` development are authored and tracked directly in this directory with `metadata: internal: true`.
* **Third-Party Skills:** Common Dart and agent development practices are vendored under the repository root at `third_party/skill-repos/` and linked here via relative symlinks.

## Managing External Skills

To add, update, or vendor external skills from upstream repositories, see the maintenance guide in [`third_party/skill-repos/README.md`](../../../../third_party/skill-repos/README.md).

## Running Evaluations (Evals)

To measure the effectiveness and quality of an agent's skill execution, we use a rubric-based LLM-as-a-judge system.

For evaluation architecture and guidelines, see [`evals/README.md`](../../evals/README.md). To run evaluations, invoke the `/run-evals` skill ([`run-evals/SKILL.md`](run-evals/SKILL.md)), which handles pre-flight workspace verification, subagent isolation, and report generation.

