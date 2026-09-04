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
- **`repo_criteria`**: Array of relative file paths to shared universal quality rubrics (such as `["evals/code_quality_rubric.json"]`).
- **`type`** *(Optional)*: Evaluation mode (`"audit"`, `"content"`, or `"triggers"`). Declares the execution stage for the suite or rubric. If omitted, structural inference applies (`positive_triggers` $\to$ triggers, `prompt` $\to$ content, criteria assertions only $\to$ content rubric).
- **`test_data`** *(Optional)*:
  - At the root level of `evals.json`: A boolean (`true` or `false`). Setting `"test_data": true` marks the file as static fixture or meta-evaluation data, instructing runners to skip it during default discovery sweeps.
  - Within an individual eval item: A relative file path or directory string pointing to static test fixture inputs used during that evaluation.
- **`agent_config`** *(Deprecated)*: Ignored by evaluation runners.

#### Minimal & Orthogonal Evaluations
- **Extend Existing Evals**: When an evaluation requirement applies across existing workflows (such as artifact metadata or output formatting), update the assertions on existing evals rather than creating a duplicate scenario.
- **Authoring Additional Evaluations**: Only create an evaluation entry when testing a distinct scenario or behavior not covered by existing evaluations.
- **Avoid Duplication**: Do NOT author multiple eval cases that test the same scenario without distinct conditions.
- **Concrete vs. Flexible Assertions**: `expected_repo_state` assertions must be concrete, binary statements that are definitively true or false based on verifiable files, diffs, or command outputs (avoiding open-ended or subjective criteria). `expected_chat_output` should remain flexible to natural language variations unless a strict output structure or checklist format is required.

### Package Rubrics (`evals/*_rubric.json`)
Package-wide quality expectations are structured into modular rubric files located in this directory:

- **Package Code Quality (`evals/code_quality_rubric.json`)**: Skills that author or modify code MUST adhere to the code quality expectations defined in `code_quality_rubric.json`. This ensures that generated code compiles cleanly, adheres to Effective Dart, works across platforms, and is placed in standard canonical directories.
- **Evaluation Quality (`evals/eval_quality_rubric.json`)**: Skills that author or modify evaluation suites MUST adhere to `eval_quality_rubric.json`.
- **Dart-Only Implementation Policy**: All test fixtures, validation scripts, evaluation harnesses, benchmark scripts, and reference tooling across this repository must be authored exclusively in Dart. Python, JavaScript, TypeScript, or other scripting languages are strictly forbidden.

## 🚀 Validating Evals Locally

Run the unit tests that check all `triggers.json` and `evals.json` files for structural consistency across the repository:

```bash
# Validate triggers.json files
dart test test/skills_triggers_test.dart

# Validate evals.json files
dart test test/skills_evals_test.dart
```

For executing live evaluations via agent orchestration (including audit, trigger, and content modes), refer directly to [`.agents/skills/run-evals/SKILL.md`](../../../.agents/skills/run-evals/SKILL.md).
