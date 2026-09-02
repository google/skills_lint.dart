---
name: run-evals
description: |-
  Run evaluations for one, multiple, or all skills using the agent orchestration framework. Supports two test types: trigger evaluations (triggers.json) and content evaluations (evals.json). Runs both test types by default when unspecified.
metadata:
  internal: true
---

# Run Skill Evals

This skill executes evaluations for AI agent skills maintained in this repository. It supports two distinct test types:

1. **Trigger Evaluations (`evals/triggers.json`)** — Verifies intent routing, trigger sensitivity, and distractor rejection before workflow execution.
2. **Content Evaluations (`evals/evals.json`)** — Verifies multi-turn tool execution, repo state mutations, and code quality rubrics in isolated workspaces.

## Invocation Modes

- `/run-evals [target]` (Default): Runs **both** Trigger Evaluations and Content Evaluations sequentially against the target skill(s).
- `/run-evals triggers [target]`: Runs only Trigger Evaluations.
- `/run-evals content [target]`: Runs only Content Evaluations.

When running both test types (the default), Trigger Evaluations execute first. After intercepting and grading Turn-1 routing, Content Evaluations execute in isolated environments, followed by a consolidated evaluation report.

---

## Trigger Evaluations (`/run-evals triggers`)

1. **Locate Triggers**: Find target `evals/triggers.json` files within `skills/` and/or `.agents/skills/`.
2. **Batch Dispatch**: For each positive trigger and distractor across the catalog, spawn a subagent in parallel:
   - Set `Role` to `Resolver-Eval-<SkillName>-<Idx>`.
   - Set `TypeName` to `self`.
   - Set `Prompt` to the exact trigger prompt string.
   - Set `Workspace` to `inherit`.
3. **Turn-1 Interception & Cutoff**:
   - Inspect Step 2 (`PLANNER_RESPONSE`) `tool_calls` in the subagent's `transcript.jsonl`.
   - Immediately terminate all subagents via `manage_subagents(Action: 'kill_all')` before subsequent tool calls or shell commands execute.
4. **Outcome Classification**:
   - **Positive Trigger**: PASS if target `SKILL.md` is loaded via `view_file`. FAIL if another skill is loaded (Collision), plain text/unrelated tool is emitted (Under-Trigger), or multiple skills are loaded (Multi-Trigger).
   - **Distractor**: PASS if target skill is not loaded (Rejected / Permitted Divergence). FAIL if target skill is loaded (Over-Trigger).
5. **Report**: Output a summary table reporting pass rates, collisions, and description boundary remedies.

---

## Content Evaluations (`/run-evals content`)

1. **Read Framework**: Read `<target-package-root>/evals/README.md` for understanding the difference between per-skill evals and cross-skill evals (where `<target-package-root>` is the directory containing the `.agents` or `skills` folder).
2. **Locate Targets**: Find target `evals/evals.json` files inside `.agents/skills/` and/or `skills/`. For cross-skill evaluations, look for `*_evals.json` files directly in `<target-package-root>/evals/`.
3. **Determine Agent Configuration**: The evaluation runner always inherits the active agent configuration/profile used in the chat where `/run-evals` was triggered (`TypeName: self`). When reporting metadata in output artifacts, record the human-readable active profile name rather than the literal parameter `"self"`. Any `agent_config` fields present in `evals.json` are ignored and have no effect on execution.
4. **Orchestrate & Isolate**:
   - **Pre-flight & Strategy Selection**: Run `git rev-parse --show-toplevel` and `git rev-parse --show-prefix` to determine repository layout:
     - **Strategy A (`Workspace: branch`)**: Use native branch workspaces when the active workspace is the Git root and a single workspace is mounted.
     - **Strategy B (Isolated Git Worktree)**: If the active workspace is a subpackage/subdirectory, multiple workspaces are mounted, or `Workspace: branch` is unsupported, create a clean worktree via `git worktree add --detach <skill-name>-workspace HEAD` and target `<skill-name>-workspace/<relative-package-prefix>`.
     - **Strict Isolation Guarantee**: NEVER run destructive setup scripts or un-isolated mutations directly in the developer's active working tree. If neither strategy can be used, halt and inform the user.
   - **Spawn Subagent(s)**: By default, run an Integration Test by spawning a single **With-Skill** subagent using the selected isolation strategy and the inherited active agent configuration (`TypeName: self`).
     - Provide the task prompt. See `resources/with_skill_execution_prompt.md` for the template. When filling in `<path-to-skill>`, you MUST use a relative path from the repository root, not an absolute path. If you are running a cross-skill evaluation, fill in `<path-to-skill>` with `"none (cross-skill meta-eval)"`. Also, replace `<target-package-root>` with the actual directory path in both templates.
     - **Only if the user explicitly requests a comparison or benchmark**, also spawn a **Baseline** subagent. See `resources/baseline_execution_prompt.md` for the template.
     - Instruct the subagent(s) to return their `git diff` and verification outputs (`dart pub get`, `dart format`, `dart analyze`, `dart test`) without committing. Ensure you instruct them to run these commands exclusively from within the `<target-package-root>` directory to avoid analyzing unrelated packages.
5. **Grade**: Parse the combined rubric (resolving `repo_criteria` + `evals.json` expectations). Use the grading instructions in `resources/agent_judge_prompt.md`. When an expectation fails, you MUST explicitly list both the expectation and what was actually found that caused the failure.
6. **Artifact & Teardown**: Grade the outputs and generate a Markdown artifact (e.g., `<skill>_eval_results.md`) containing the metadata, pass/fail rationale, and raw diffs/stdout.
   - **Reporting Integrity & Metadata**: When recording execution metadata (model, effort level, agent configuration), ONLY record values verified through real environment/session data. NEVER guess, assume, or fabricate model names, effort levels, or configurations. In VS Code / Jetski environments, the primary source to verify the active model and effort level is the global state SQLite database (`<user-data-dir>/User/globalStorage/state.vscdb`, e.g. `~/Library/Application Support/Jetski/User/globalStorage/state.vscdb` on macOS), cross-referencing the active model ID in `antigravityUnifiedStateSync.modelPreferences` against `antigravityUnifiedStateSync.userStatus`. If the exact model name or effort level cannot be verified from the environment, record it as `Active session model (unspecified)` or omit the field.
   - If an isolated worktree was used (Strategy B), clean it up via `git worktree remove --force <skill-name>-workspace`.
