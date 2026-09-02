# Skill Evaluations

Architecture, rubrics, and instructions for evaluating AI agent skills authored and maintained in this repository.
**Note:** These evaluations are essentially unit tests for the skills within the `skills_lint` package and its internal ecosystem. They are *not* intended to be a generic evaluation framework for other agent client plugins or tools outside of this specific domain.

## What Should (and Shouldn't) Be Evaluated

**DO Evaluate:**
- Core workflows of a skill (e.g., adding a dependency, running validation checks).
- Specific edge cases that a skill claims to handle (e.g., legacy integration paths without `--fix`).
- Whether a skill correctly leaves the repository in a compilable, passing state.

**DO NOT Evaluate:**
- Trivial syntax formatting that `dart format` already fixes perfectly.
- Complete system architectures that take longer than a few minutes to generate and verify.
- Skills that are outside the scope of `skills_lint` (e.g. general flutter app creation).
- Duplicate evaluation scenarios without introducing distinct conditions (e.g., testing the exact same workflow multiple times with redundant assertions).

## Core Principles & Architecture

Evaluations in this repository support **two test types** to evaluate both intent routing and workflow completion:

### 1. Trigger Evals (`<skill_dir>/evals/triggers.json`)
Evaluates **Intent Routing & Skill Discovery**: tests how AI agent intent routers discover and select skills from the active skills catalog before full workflow execution begins.
- **`skill`**: Name of the target skill.
- **`positive_triggers`**: Array of in-domain user prompts that MUST activate this skill.
- **`distractors`**: Array of out-of-domain or boundary prompts that must NOT activate this skill.

### 2. Content Evals (`<skill_dir>/evals/evals.json`)
Evaluates **Workflow Execution & Workspace Mutations**: tests multi-turn sandbox sessions to verify the agent produces expected chat outputs and repository mutations.
- **`prompt`**: Realistic user prompt testing primary or edge-case workflows.
- **`expected_chat_output`**: High-level narrative summary of what the LLM should say/give to the user.
- **`expected_repo_state`**: Array of discrete, testable assertions regarding the end state of the repository and tracked files.
- **`repo_criteria`**: Array of relative file paths to shared universal quality rubrics (e.g., `["evals/code_quality_rubric.json"]`).
- **`test_data`** *(Optional)*: Relative file path or directory containing static test fixtures or mock inputs used during evaluation.
- **`agent_config`** *(Deprecated)*: Ignored by evaluation runners.

#### Minimal & Orthogonal Evaluations
- **Extend Existing Evals**: When an evaluation requirement applies across existing workflows (such as artifact metadata or output formatting), update the assertions on existing evals rather than creating a duplicate scenario.
- **Create New Evals**: Only create a new eval entry when testing a distinct scenario or behavior not covered by existing evals.
- **Avoid Duplication**: Do NOT author multiple eval cases that test the same scenario without distinct conditions.
- **Concrete vs. Flexible Assertions**: `expected_repo_state` assertions must be concrete, binary statements that are definitively true or false based on verifiable files, diffs, or command outputs (avoiding open-ended or subjective criteria). `expected_chat_output` should remain flexible to natural language variations unless a strict output structure or checklist format is required.

### Cross-Skill Rubrics (`evals/*_rubric.json`)
Universal skill quality expectations are structured into modular rubric classes that apply broadly across skills.

## Cross-Cutting Rules
- **Code Quality**: Skills that author or modify code MUST adhere to the universal code quality expectations defined in `code_quality_rubric.json`. This ensures that generated code compiles cleanly, adheres to Effective Dart, works across platforms, and is placed in standard canonical directories.
- **Evaluation Quality**: Skills that author or modify evaluation suites MUST adhere to `eval_quality_rubric.json`.

## 🚀 Running & Validating Evals Locally

### 1. Validate Evals & Triggers Structural Consistency
Run the unit tests that check all `triggers.json` and `evals.json` files for structural consistency across the repository:

```bash
# Validate triggers.json files
dart test test/skills_triggers_test.dart

# Validate evals.json files
dart test test/skills_evals_test.dart
```

### 2. Running Evals via Agent Orchestration (`/run-evals`)
Use the `/run-evals` skill to run evaluations. All execution logic, subagent dispatch, and Turn-1 interception rules are defined directly in [`run-evals/SKILL.md`](../../../.agents/skills/run-evals/SKILL.md).

* **Run Both (Default)**: `/run-evals [target_dir]`
* **Run Trigger Evaluations Only**: `/run-evals triggers [target_dir]`
* **Run Content Evaluations Only**: `/run-evals content [target_dir]`

### 3. Testing Meta-Evals (Testing the Rubrics)
To ensure our universal rubrics correctly catch anti-patterns (and permit clean code), standalone cross-skill evaluations are defined as `evals/*_evals.json` files (e.g., `evals/code_quality_rubric_evals.json`, `evals/eval_quality_rubric_evals.json`). These files contain evals specifying `test_data` fields targeting static fixtures located in `evals/test_data/`.

Note: Default `/run-evals` discovery explicitly ignores `evals/test_data/**` fixtures so that fixture evals are never executed as live skill tests. To run meta-evals and verify rubrics, explicitly target the standalone rubric evaluation file: `/run-evals content evals/code_quality_rubric_evals.json` or `/run-evals content evals/eval_quality_rubric_evals.json`.
