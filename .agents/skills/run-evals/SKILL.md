---
name: run-evals
description: |-
  Run evaluations for one, multiple, or all skills using the agent orchestration framework. Supports three evaluation modes: audit evaluations (eval_quality_rubric.json), trigger evaluations (triggers.json), and content evaluations (evals.json). Runs all three modes and generates a comprehensive evaluation report across all stages.
metadata:
  internal: true
---

# Run Skill Evals

This skill executes evaluations for AI agent skills maintained in this repository. It supports three distinct evaluation modes:

1. **Audit Evaluations (`evals/eval_quality_rubric.json`)** — Statically inspects `evals.json` test suites to verify scenario orthogonality, non-duplication, and discrete binary assertions before executing tasks.
2. **Trigger Evaluations (`evals/triggers.json`)** — Verifies intent routing, trigger sensitivity, and distractor rejection before workflow execution.
3. **Content Evaluations (`evals/evals.json`)** — Verifies multi-turn tool execution, repo state mutations, and code quality rubrics in isolated workspaces.

## Invocation Modes & CLI Grammar

The runner requires one of the **5 reserved keywords** (`content`, `triggers`, `audit`, `all`, `help`). Invoking `/run-evals` without arguments (default usage) or with an unrecognized keyword displays the command reference guide and exits without executing evaluations.

| Command | Target Scope | Description |
| :--- | :--- | :--- |
| `/run-evals` | **Usage Guide** (Default) | Displays this command reference guide and exits. |
| `/run-evals content [all \| <skill \| file_path>]` | **Multi-Turn Content** | Runs task execution in isolated workspaces and grades workspace state against code quality standards (`evals/code_quality_rubric.json`). Accepts `all` or a specific skill/file path. |
| `/run-evals triggers [all \| <skill>]` | **Trigger Router Test** | Evaluates intent routing and distractor rejection across `triggers.json` files with Turn-1 cutoff. Accepts `all` or a specific skill. |
| `/run-evals audit [all \| <skill \| file_path>]` | **Static Audit** | Statically audits evaluation suites against evaluation quality standards (`evals/eval_quality_rubric.json`). Accepts `all` or a specific skill/file path. |
| `/run-evals all [skill]` | **All Skills + Test Data** | Runs the full **Audit -> Triggers -> Content** staged pipeline across all skills (or a specified `<skill>`), including suites and meta-evals marked with `"test_data": true`. |
| `/run-evals help` | **Usage Guide** | Displays this command reference and exits. |

### Data-Driven Execution Architecture
The evaluation framework uses data structure, rather than directory layout or hardcoded filenames, to govern evaluation discovery and execution:

1. **Rubric Type Partitioning (`"type": "audit" | "content"`)**:
   - Rubrics define their evaluation phase through the root `"type"` field:
     - `"type": "audit"` -> Statically verified during Stage 1 (Audit) without spawning execution subagents.
     - `"type": "content"` -> Evaluated by the Agent Judge during Stage 3 (Content) after multi-turn tool execution.
   - When a skill declares `"repo_criteria": ["evals/..."]`, the runner checks each referenced rubric file's `"type"` field to determine whether it applies during the Audit or Content phase.
   - **Fallback Inference**: If `"type"` is omitted, structural inference applies: suites containing `positive_triggers` run as triggers, suites containing `prompt` run as content, and files containing only criteria assertions run as content rubrics.
2. **Pure Data-Driven Discovery (`"test_data": true`)**:
   - The root-level `"test_data": true` boolean in any JSON file marks it as test fixture or meta-evaluation data.
   - Default discovery sweeps (`/run-evals content`, `/run-evals triggers`, `/run-evals audit`) without `all` skip any file containing `"test_data": true` at its root, regardless of directory location.
   - **Full Pipeline (`/run-evals all [skill]`)**: Runs all evaluation stages (**Audit -> Triggers -> Content**) across all skills (or a specified target `<skill>`), including suites and meta-evals marked with `"test_data": true`.
   - **Mode-Specific Discovery (`/run-evals <mode> all`)**: Passing `all` to a single evaluation mode (such as `/run-evals content all`, `/run-evals triggers all`, or `/run-evals audit all`) runs **only** that specific mode, but expands discovery to also include suites and fixtures marked with `"test_data": true` for that mode.
   - **Explicit Target Invocations**: Specifying an explicit file target path (such as `/run-evals content packages/skills_lint/evals/code_quality_rubric_evals.json`) directly evaluates that targeted file, including files marked with `"test_data": true`.

### Multi-Stage Pipeline: `Audit -> Triggers -> Content`
When executing evaluation suites, the runner runs all stages across targeted skills and generates a comprehensive aggregate report:
1. **Stage 1: Audit (Static Quality Inspection)** — Evaluates target `evals.json` files against all referenced `"type": "audit"` rubrics (such as `evals/eval_quality_rubric.json`). Checks for scenario orthogonality, absence of duplicate scenarios, and concrete binary assertions. Records diagnostic findings and proceeds to Stage 2.
2. **Stage 2: Triggers (Turn-1 Router Test)** — Dispatches parallel subagents to test intent routing and distractor rejection with Turn-1 cutoff. Records routing outcomes (passes, collisions, under-triggers, distractors) and proceeds to Stage 3.
3. **Stage 3: Content (Multi-Turn Execution & Workspace Mutations)** — Spawns subagents in isolated workspaces to execute tasks and grades repository mutations against referenced `"type": "content"` rubrics (such as `evals/code_quality_rubric.json`) and suite assertions.
4. **Consolidated Reporting** — Produces an aggregate evaluation report containing complete results, diagnostics, and metrics across all three stages.

---

## Audit Evaluations (`/run-evals audit`)

1. **Locate Targets**: Find target `evals/evals.json` files within `skills/` and `.agents/skills/`, or the specified explicit file path.
   - **Discovery Filter**: Exclude files marked with `"test_data": true` unless `all` or an explicit file target is provided.
2. **Load Rubric**: Load `packages/skills_lint/evals/eval_quality_rubric.json` (resolving criteria declared in `repo_criteria`).
3. **Static Evaluation**: Statically inspect the target `evals.json` against the universal evaluation rules:
   - **`eval_redundancy_and_consolidation`**: Verify that all eval entries are orthogonal, test distinct scenarios, and do not repeat duplicate workflows without distinct conditions.
   - **`binary_repo_state_assertions`**: Verify that all `expected_repo_state` assertions are discrete, binary conditions that can be evaluated definitively as true or false via files, diffs, or command output (avoiding vague, subjective, or aesthetic criteria).
4. **Report Findings**: Output audit status. When running as part of a multi-stage pipeline, record all passed and failed assertions for each eval ID and proceed to the next stage.

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
2. **Locate Targets**: Find target `evals/evals.json` files inside `.agents/skills/` and/or `skills/`. For cross-skill evaluations, look for `*_evals.json` files directly in `<target-package-root>/evals/`. Note: Any evaluation suites marked with `"test_data": true` at the root of `evals.json` are static fixture data for meta-evaluations and are ignored by default `/run-evals` discovery.
3. **Determine Agent Configuration**: The evaluation runner always inherits the active agent configuration/profile used in the chat where `/run-evals` was triggered (`TypeName: self`). When reporting metadata in output artifacts, record the human-readable active profile name rather than the literal parameter `"self"`. Any `agent_config` fields present in `evals.json` are ignored and have no effect on execution.
4. **Orchestrate & Isolate**:
   - **Pre-flight & Strategy Selection**: Run `git rev-parse --show-toplevel` and `git rev-parse --show-prefix` to determine repository layout:
     - **Strategy A (`Workspace: branch`)**: Use native branch workspaces when the active workspace is the Git root and a single workspace is mounted.
     - **Strategy B (Isolated Git Worktree)**: If the active workspace is a subpackage/subdirectory, multiple workspaces are mounted, or `Workspace: branch` is unsupported, create a clean worktree via `git worktree add --detach <skill-name>-workspace HEAD` and target `<skill-name>-workspace/<relative-package-prefix>`.
     - **Strict Isolation Guarantee**: NEVER run destructive setup scripts or un-isolated mutations directly in the developer's active working tree. If neither strategy can be used, halt and inform the user.
   - **Spawn Subagent(s)**: By default, run an Integration Test by spawning a single **With-Skill** subagent using the selected isolation strategy and the inherited active agent configuration (`TypeName: self`).
     - Provide the task prompt. See [resources/with_skill_execution_prompt.md](resources/with_skill_execution_prompt.md) for the template. When filling in `<path-to-skill>`, you MUST use a relative path from the repository root, not an absolute path. If you are running a cross-skill evaluation, fill in `<path-to-skill>` with `"none (cross-skill meta-eval)"`. Also, replace `<target-package-root>` with the actual directory path in both templates.
     - **Only if the user explicitly requests a comparison or benchmark**, also spawn a **Baseline** subagent. See [resources/baseline_execution_prompt.md](resources/baseline_execution_prompt.md) for the template.
     - Instruct the subagent(s) to return their `git diff` and verification outputs (`dart pub get`, `dart format`, `dart analyze`, `dart test`) without committing. Ensure you instruct them to run these commands exclusively from within the `<target-package-root>` directory to avoid analyzing unrelated packages.
5. **Grade**: Parse the combined rubric (resolving `repo_criteria` + `evals.json` expectations). Use the grading instructions in [resources/agent_judge_prompt.md](resources/agent_judge_prompt.md). When an expectation fails, you MUST explicitly list both the expectation and what was actually found that caused the failure.
6. **Artifact & Teardown**: Grade the outputs and generate a Markdown artifact (e.g., `<skill>_eval_results.md`) containing the metadata, pass/fail rationale, and raw diffs/stdout.
   - **Reporting Integrity & Execution Metadata**: When recording execution metadata in evaluation artifacts and pull request comments:
     - **Commit Hash**: Record the HEAD commit hash (`git rev-parse HEAD`) active at the time the evaluation was executed.
     - **Subagent Model Resolution**:
       - Capture the `conversationId` returned from `invoke_subagent`.
       - After the subagent completes, inspect the subagent's generation metadata from `~/.gemini/jetski/conversations/<conversationId>.db` (querying `gen_metadata`) to extract the exact model slug (e.g., `gemini-3.6-flash`) that executed the task.
       - If the subagent database is unavailable, fall back to `Active session model (unspecified)`. NEVER guess, assume, or fabricate model names, effort levels, or configurations.
     - **Agent Configuration**: Record the human-readable profile name inherited by the subagent (e.g., `reidbaker-agent`) rather than the literal parameter `"self"`.
   - **Formatting Clean Tables & Comment Links**: When formatting Markdown evaluation matrices and pull request comments, avoid raw `#<number>` tokens (e.g. write `Eval 1` or link to the eval file instead of `#1`) to avoid GitHub autolinking numbers to unrelated issues or pull requests.
   - If an isolated worktree was used (Strategy B), clean it up via `git worktree remove --force <skill-name>-workspace`.
