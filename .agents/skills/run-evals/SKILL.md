---
name: run-evals
description: |-
  Use this skill to execute evaluation sweeps on AI agent skills across the repository. Supports Phase 1 Resolver Trigger Evaluations (evals/triggers.json) and Phase 2 Workflow Sandbox Evaluations (evals/evals.json).
metadata:
  internal: true
---

# Running Skill Evaluations

This skill executes automated evaluation sweeps for skills authored in this repository. It provides two testing tiers:

1. **Phase 1: Resolver Trigger Evaluations (`evals/triggers.json`)** — Verifies intent routing, trigger sensitivity, and distractor rejection before workflow execution.
2. **Phase 2: Workflow Sandbox Evaluations (`evals/evals.json`)** — Verifies multi-turn tool execution, repo state mutations, and code quality rubrics in isolated sandbox workspaces.

---

## 1. Phase 1: Running Resolver Trigger Evaluations

### Command Syntax
```text
/run-evals triggers [target_directory]
```
If `target_directory` is omitted, defaults to scanning all skill directories defined in `skills_lint.yaml` (`skills/` and `.agents/skills/`).

### Execution Protocol

1. **Discovery**:
   - Locate all `<skill_dir>/evals/triggers.json` files within the target scope.
   - Parse `skill`, `positive_triggers`, and `distractors`.

2. **Parallel Subagent Dispatch**:
   - For every trigger prompt, dispatch a subagent using `invoke_subagent`.
   - Set `Role` to `Resolver-Eval-<SkillName>-<TriggerIndex>` (e.g. `Resolver-Eval-Setup-0`).
   - Set `TypeName` to `self`.
   - Set `Prompt` to the exact trigger prompt string.
   - Set `Workspace` to `inherit` (or `branch` for complete isolation).

3. **Turn-1 Interception & Cutoff**:
   - Once Turn 1 produces its planner response, open the subagent's `transcript.jsonl` located at:
     `<appDataDir>/brain/<conversationId>/.system_generated/logs/transcript.jsonl`
   - Inspect Step 2 (`PLANNER_RESPONSE`) `tool_calls`.
   - Immediately terminate all subagents via `manage_subagents(Action: 'kill_all')` before they execute Phase 2 file modifications or terminal commands.

4. **Outcome Classification**:
   Extract any `view_file` calls targeting `skills/<skill_name>/SKILL.md` (or dedicated skill tool calls) and grade against the matrix:

   | Trigger Type | Turn-1 Action | Classification | Grade |
   | :--- | :--- | :--- | :--- |
   | **Positive Trigger** | Calls `view_file` on target `SKILL.md` | `RESOLVED` | **PASS** |
   | **Positive Trigger** | Calls `view_file` on a different `SKILL.md` | `COLLISION` | **FAIL** |
   | **Positive Trigger** | Plain text only / Unrelated tool calls | `UNDER_TRIGGER` | **FAIL** |
   | **Positive Trigger** | Calls `view_file` on multiple skills | `MULTI_TRIGGER` | **FAIL** |
   | **Distractor** | Calls `view_file` on target `SKILL.md` | `OVER_TRIGGER` | **FAIL** |
   | **Distractor** | Plain text only (no skill loaded) | `REJECTED` | **PASS** |
   | **Distractor** | Calls `view_file` on a different skill | `PERMITTED_DIVERGENCE` | **PASS** |

5. **Diagnostic Summary Report**:
   Print a formatted summary table:

   ```text
   === Resolver Trigger Sweep ===
   Catalog Scope: repository-local | Skills: 2 | Total Triggers: 16 | Concurrency: 16

   ✓ dart-skills-lint-setup:      4/4 triggers resolved (100%)
   ✓ dart-skills-lint-validation: 4/4 triggers resolved (100%)
   ✓ Distractor Rejection:        8/8 rejected (100%)

   Result: ALL RESOLVER TRIGGERS PASSED (16/16)
   ```

   If failures occur, report explicit diagnostic failure breakdowns:
   ```text
   FAILURES DETECTED (1/16 failed):

   1. [COLLISION / SHADOWED]
      Prompt:   "Check my skill files for lint errors"
      Expected: dart-skills-lint-validation
      Actual:   dart-skills-lint-setup (INTERCEPTED)
      Analysis: dart-skills-lint-setup intercepted prompt intended for validation.
      Remedy:   Clarify setup vs. validation boundaries in dart-skills-lint-setup/SKILL.md.
   ```

---

## 2. Phase 2: Running Workflow Sandbox Evaluations

### Command Syntax
```text
/run-evals workflows [target_directory]
```

### Execution Protocol
1. Locate `<skill_dir>/evals/evals.json`.
2. For each eval scenario:
   - Create an isolated branch/workspace.
   - Launch subagent to execute the workflow.
   - Run assertions defined in `expected_repo_state` and verify against `repo_criteria` rubrics (`code_quality_rubric.json`).
3. Report pass/fail status per test case.
