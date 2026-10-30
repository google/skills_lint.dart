---
name: run-evals
description: |-
  Executes AI agent skill evaluations with staged execution pipelines and data-driven discovery. Requires a reserved keyword (content, triggers, audit, all, help); running without arguments displays the CLI usage guide.
metadata:
  internal: true
---

# Run Skill Evals

This skill executes evaluations for AI agent skills maintained in this repository. It supports three distinct evaluation modes:

1. **Audit Evaluations** — Statically inspects target `evals.json` test suites against all referenced audit rubrics declared in `repo_criteria` before executing tasks.
2. **Trigger Evaluations** — Verifies intent routing, trigger sensitivity, and distractor rejection before workflow execution.
3. **Content Evaluations** — Verifies multi-turn tool execution, repo state mutations, and code quality rubrics in isolated workspaces.

## Invocation Modes & CLI Grammar

The runner requires one of the **5 reserved keywords** (`content`, `triggers`, `audit`, `all`, `help`). Invoking `/run-evals` without arguments (default usage) or with an unrecognized keyword displays the command reference guide and exits without executing evaluations.

| Command | Target Scope | Description |
| :--- | :--- | :--- |
| `/run-evals` | **Usage Guide** (Default) | Displays this command reference guide and exits. |
| `/run-evals content [all \| <skill \| file_path>]` | **Multi-Turn Content** | Runs task execution in isolated workspaces and grades workspace state against content rubrics declared in `repo_criteria` and suite assertions. Accepts `all` or a specific skill/file path. |
| `/run-evals triggers [all \| <skill>]` | **Trigger Router Test** | Evaluates intent routing and distractor rejection across `triggers.json` files with Turn-1 cutoff. Accepts `all` or a specific skill. |
| `/run-evals audit [all \| <skill \| file_path>]` | **Static Audit** | Statically audits evaluation suites against audit rubrics declared in `repo_criteria`. Accepts `all` or a specific skill/file path. |
| `/run-evals all [skill]` | **All Skills + Test Data** | Runs the full **Audit -> Triggers -> Content** staged pipeline across all skills (or a specified `<skill>`), including suites and meta-evals marked with `"test_data": true`, and produces one aggregate report covering all three stages. |
| `/run-evals help` | **Usage Guide** | Displays this command reference and exits. |

### Discovery & Target Resolution

See [`evals/README.md`](../../../packages/skills_lint/evals/README.md#evaluation-file--rubric-schema) for the suite and rubric schema (`repo_criteria`, `"type"`, `"test_data"`).

1. **Target Resolution**:
   - **`<skill>` name**: Resolve `.agents/skills/<skill>` first, falling back to `<target-package-root>/skills/<skill>` (where `<target-package-root>` is the package directory containing `skills/` and `evals/`, such as `packages/skills_lint`).
   - **Explicit `<file_path>`**: Evaluate the targeted file directly (for example, [`packages/skills_lint/evals/code_quality_rubric_evals.json`](../../../packages/skills_lint/evals/code_quality_rubric_evals.json)), even when marked with `"test_data": true`.
   - **Catalog sweep** (no target or `all`): Discover top-level skill suites (`.agents/skills/<skill>/evals/` and `<target-package-root>/skills/<skill>/evals/`) and top-level cross-skill suites (`<target-package-root>/evals/*_evals.json`). Nested files inside `test_data/` or `resources/` subdirectories are fixture inputs and are never discovered as test suites.
2. **Test Data Filtering (`"test_data": true`)**:
   - Default mode sweeps (`/run-evals content`, `/run-evals triggers`, `/run-evals audit`) skip any suite with `"test_data": true` at the root.
   - Passing `all` (`/run-evals all [skill]` or `/run-evals <mode> all`) or an explicit `<file_path>` includes suites marked with `"test_data": true`.

---

## Audit Evaluations (`/run-evals audit`)

1. **Load Referenced Rubrics**: Resolve target `evals.json` and `*_evals.json` suites per [Discovery & Target Resolution](#discovery--target-resolution). Inspect `repo_criteria` in each target suite and load only the referenced criteria files that declare `"type": "audit"`. If a target declares no audit rubrics in `repo_criteria`, skip static audit checks for that target.
2. **Static Evaluation**: Statically inspect the target `evals.json` against each criteria assertion defined in the loaded audit rubric files without spawning execution subagents.
   - **Per-Item Test Data Meta-Evaluations**: If an eval item in a meta-eval suite (such as `eval_quality_rubric_evals.json`) specifies a per-item `"test_data"` file path, statically inspect the fixture file referenced in `test_data` against the audit rubric assertions.
3. **Report Findings**: Output audit status. When running as part of a multi-stage pipeline, record all passed and failed assertions for each eval ID and proceed to the next stage.

---

## Trigger Evaluations (`/run-evals triggers`)

1. **Batch Dispatch**: Resolve target `evals/triggers.json` files per [Discovery & Target Resolution](#discovery--target-resolution). For each positive trigger and distractor across the resolved files, spawn a subagent in parallel:
   - Set `Role` to `Resolver-Eval-<SkillName>-<Idx>`.
   - Set `TypeName` to `self`.
   - Set `Prompt` to the exact trigger prompt string. A `positive_triggers` entry is either a prompt string or an object `{"prompt": "...", "permitted_co_triggers": ["<skill>", ...]}`; for an object, use its `prompt` value.
   - Set `Workspace` to `inherit`.
2. **Turn-1 Interception & Cutoff**:
   - Inspect the `tool_calls` of the first `PLANNER_RESPONSE` step that has `tool_calls` in the subagent's transcript. Read the transcript from the location the harness reports when it creates the subagent (for example, the `logAbsoluteUri` field that `invoke_subagent` returns). If the harness reports no location, ask the harness where it stores subagent transcripts. Do not assume a fixed path.
   - Immediately terminate all subagents via `manage_subagents(Action: 'kill_all')` before subsequent tool calls or shell commands execute.
3. **Outcome Classification**:
   - **Positive Trigger**: PASS if only the target `SKILL.md` is loaded via the file-read tool (`read_file`; older builds call it `view_file`). PASS (Co-Trigger) if the target `SKILL.md` is loaded and every other loaded skill is listed in the entry's `permitted_co_triggers`. FAIL if another skill is loaded instead of the target (Collision), plain text/unrelated tool is emitted (Under-Trigger), or the target is loaded together with any skill not listed in `permitted_co_triggers` (Multi-Trigger). A plain string entry has no permitted co-triggers.
   - **Distractor**: PASS if target skill is not loaded (Rejected / Permitted Divergence). FAIL if target skill is loaded (Over-Trigger).
4. **Report**: Output a summary table reporting pass rates, collisions, and description boundary remedies. Count PASS (Co-Trigger) results as passes and list the co-loaded skills.

---

## Content Evaluations (`/run-evals content`)

1. **Resolve Targets & Agent Configuration**: Resolve target `evals.json` and `*_evals.json` suites per [Discovery & Target Resolution](#discovery--target-resolution). The evaluation runner always inherits the active agent configuration/profile used in the chat where `/run-evals` was triggered (`TypeName: self`). When reporting metadata in output artifacts, record the human-readable active profile name rather than the literal parameter `"self"`. Any `agent_config` fields present in `evals.json` are ignored and have no effect on execution.
2. **Orchestrate & Isolate**:
   - **Pre-flight & Strategy Selection**: Run `git rev-parse --show-toplevel` and `git rev-parse --show-prefix` to determine repository layout:
     - **Strategy A (`Workspace: branch`)**: Use native branch workspaces when the active workspace is the Git root and a single workspace is mounted.
     - **Strategy B (Isolated Git Worktree)**: If the active workspace is a subpackage/subdirectory, multiple workspaces are mounted, or `Workspace: branch` is unsupported, create a clean worktree via `git worktree add --detach <skill-name>-workspace HEAD` and target `<skill-name>-workspace/<relative-package-prefix>`.
     - **Strict Isolation Guarantee**: NEVER run destructive setup scripts or un-isolated mutations directly in the developer's active working tree. If neither strategy can be used, halt and inform the user.
   - **Spawn Subagent(s)**: By default, run an Integration Test by spawning a single **With-Skill** subagent using the selected isolation strategy and the inherited active agent configuration (`TypeName: self`).
     - Provide the task prompt. See [resources/with_skill_execution_prompt.md](resources/with_skill_execution_prompt.md) for the template. When filling in `<path-to-skill>`, you MUST use a relative path from the repository root, not an absolute path. If you are running a cross-skill evaluation, fill in `<path-to-skill>` with `"none (cross-skill meta-eval)"`. Also, replace `<target-package-root>` with the actual directory path in both templates.
     - **Only if the user explicitly requests a comparison or benchmark**, also spawn a **Baseline** subagent. See [resources/baseline_execution_prompt.md](resources/baseline_execution_prompt.md) for the template.
     - Instruct the subagent(s) to return their `git diff` and verification outputs (`dart pub get`, `dart format`, `dart analyze`, `dart test`) without committing. Ensure you instruct them to run these commands exclusively from within the `<target-package-root>` directory to avoid analyzing unrelated packages.
3. **Grade**: Parse the combined rubric (resolving referenced `"type": "content"` rubrics from `repo_criteria` + `evals.json` expectations). Use the grading instructions in [resources/agent_judge_prompt.md](resources/agent_judge_prompt.md). When an expectation fails, you MUST explicitly list both the expectation and what was actually found that caused the failure.
4. **Artifact & Teardown**: Grade the outputs and generate a Markdown artifact (e.g., `<skill>_eval_results.md`) containing the metadata, pass/fail rationale, and raw diffs/stdout.
   - **Reporting Integrity & Execution Metadata**: When recording execution metadata in evaluation artifacts and pull request comments:
     - **Commit Hash**: Record the HEAD commit hash (`git rev-parse HEAD`) active at the time the evaluation was executed.
     - **Subagent Model Resolution**:
       - Capture the `conversationId` returned from `invoke_subagent`.
       - After the subagent completes, get the exact model slug (e.g., `gemini-3.6-flash`) that executed the task from the harness's record of that conversation. Use what the harness reports for the `conversationId`, or ask the harness where it stores per-conversation generation metadata.
         - As a fallback only, some harnesses store this metadata in a SQLite database with a `gen_metadata` table. Known examples: Jetski uses `~/.gemini/jetski/conversations/<conversationId>.db`, and the Antigravity CLI uses `~/.gemini/antigravity-cli/conversations/<conversationId>.db`.
       - If the subagent database is unavailable, fall back to `Active session model (unspecified)`. NEVER guess, assume, or fabricate model names, effort levels, or configurations.
     - **Agent Configuration**: Record the human-readable profile name inherited by the subagent (e.g., `reidbaker-agent`) rather than the literal parameter `"self"`.
   - **Formatting Clean Tables & Comment Links**: When formatting Markdown evaluation matrices and pull request comments, avoid raw `#<number>` tokens (e.g. write `Eval 1` or link to the eval file instead of `#1`) to avoid GitHub autolinking numbers to unrelated issues or pull requests.
   - If an isolated worktree was used (Strategy B), clean it up via `git worktree remove --force <skill-name>-workspace`.
