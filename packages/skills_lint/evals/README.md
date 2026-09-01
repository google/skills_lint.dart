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
- **`agent_config`** *(Optional, Deprecated)*: The model configuration/profile to spawn. When omitted, the `/run-evals` harness automatically inherits the active runner's environment configuration.

### Cross-Skill Rubrics (`evals/*_rubric.json`)
Universal skill quality expectations are structured into modular rubric classes that apply broadly across skills.

## Cross-Cutting Rules
Skills that author or modify code MUST adhere to the universal code quality expectations defined in `code_quality_rubric.json`. This ensures that generated code compiles cleanly, adheres to Effective Dart, works across platforms, and is placed in standard canonical directories.

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
Use the `/run-evals` skill to run evaluations. All execution logic, subagent dispatch, and Turn-1 interception rules are defined directly in [`run-evals/SKILL.md`](../.agents/skills/run-evals/SKILL.md).

* **Run Both (Default)**: `/run-evals [target_dir]`
* **Run Trigger Evaluations Only**: `/run-evals triggers [target_dir]`
* **Run Content Evaluations Only**: `/run-evals content [target_dir]`

#### Agent Configuration & Evaluation Metadata
The evaluation runner automatically inherits the agent configuration/profile used in the chat where `/run-evals` was triggered (with fallback to `agent_config` if explicitly specified in an `evals.json` entry). Evaluation results artifacts record execution metadata, including the model name, effort level, and agent configuration when available.

### 3. Testing Meta-Evals (Testing the Rubrics)
To ensure our universal rubrics correctly catch anti-patterns (and permit clean code), standalone cross-skill evaluations are defined as `evals/*_evals.json` files (e.g., `evals/code_quality_rubric_evals.json`). These files contain evals strictly intended to grade static fixtures located in `evals/test_data/`.

To run the meta-evals and verify the rubrics, invoke `/run-evals content` on the standalone `code_quality_rubric_evals.json` file.
