---
name: run-evals
description: Run evaluations for one, multiple, or all skills using the agent orchestration framework. Make sure to use this skill whenever the user asks to run evals, test a skill's performance, run benchmarks, or compare baseline versus with-skill execution.
metadata:
  internal: true
---

# Run Skill Evals

1. **Read Framework**: Read `<target-package-root>/evals/README.md` for understanding the difference between per-skill evals and cross-skill evals (where `<target-package-root>` is the directory containing the `.agents` or `skills` folder).
2. **Locate Targets**: Find target `evals/evals.json` files inside `.agents/skills/` and/or `skills/`. For cross-skill evaluations, look for `*_evals.json` files directly in `<target-package-root>/evals/`.
3. **Determine Agent Configuration**: Check the `agent_config` field in the target target JSON file to determine the environment/harness to spawn. If `agent_config` is `"bare-agent"`, spawn a subagent with the `bare-agent` profile. If it is a specific contributor profile (e.g. `"reidbaker-agent"`), use that profile to provide the necessary contributor context.
4. **Orchestrate & Isolate**:
   - **Pre-flight & Strategy Selection**: Run `git rev-parse --show-toplevel` and `git rev-parse --show-prefix` to determine repository layout:
     - **Strategy A (`Workspace: branch`)**: Use native branch workspaces when the active workspace is the Git root and a single workspace is mounted.
     - **Strategy B (Isolated Git Worktree)**: If the active workspace is a subpackage/subdirectory, multiple workspaces are mounted, or `Workspace: branch` is unsupported, create a clean worktree via `git worktree add --detach <skill-name>-workspace HEAD` and target `<skill-name>-workspace/<relative-package-prefix>`.
     - **Strict Isolation Guarantee**: NEVER run destructive setup scripts or un-isolated mutations directly in the developer's active working tree. If neither strategy can be used, halt and inform the user.
   - **Spawn Subagent(s)**: By default, run an Integration Test by spawning a single **With-Skill** subagent using the selected isolation strategy and the identified `agent_config`.
     - Provide the task prompt. See `resources/with_skill_execution_prompt.md` for the template. When filling in `<path-to-skill>`, you MUST use a relative path from the repository root, not an absolute path. If you are running a cross-skill evaluation, fill in `<path-to-skill>` with `"none (cross-skill meta-eval)"`. Also, replace `<target-package-root>` with the actual directory path in both templates.
     - **Only if the user explicitly requests a comparison or benchmark**, also spawn a **Baseline** subagent. See `resources/baseline_execution_prompt.md` for the template.
     - Instruct the subagent(s) to return their `git diff` and verification outputs (`dart pub get`, `dart format`, `dart analyze`, `dart test`) without committing. Ensure you instruct them to run these commands exclusively from within the `<target-package-root>` directory to avoid analyzing unrelated packages.
     - **CRITICAL**: You must explicitly warn the subagent(s) to confine all file edits strictly to their current working directory and avoid using absolute paths to modify the parent workspace.
5. **Grade**: Parse the combined rubric (resolving `repo_criteria` + `evals.json` expectations). Use the grading instructions in `resources/agent_judge_prompt.md`. When an expectation fails, you MUST explicitly list both the expectation and what was actually found that caused the failure.
6. **Artifact & Teardown**: Grade the outputs and generate a Markdown artifact (e.g., `<skill>_eval_results.md`) containing the metadata, pass/fail rationale, and raw diffs/stdout. If an isolated worktree was used (Strategy B), clean it up via `git worktree remove --force <skill-name>-workspace`.
