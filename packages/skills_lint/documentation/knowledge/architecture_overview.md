# Architecture Overview: Agent Skills Linter (`skills_lint`)

This document provides a high-level architectural overview of the `skills_lint` codebase. It outlines the core architectural boundaries, execution lifecycle, durable design patterns, and rejected architectural anti-patterns.

For code style, Effective Dart conventions, and documentation standards, see the [Style Guide](style_guide.md).

## 🧱 Architectural Boundaries

The system is organized into decoupled layers, separating command-line orchestration, configuration management, pure validation logic, suppression persistence, and output reporting.

### 1. [CLI & Orchestration Layer](../../lib/src/entry_point.dart)
The orchestration layer manages the execution session from invocation to termination.
- **Invocation & Environment Discovery:** Parses command-line inputs, discovers target skill directories (resolving workspace defaults when no explicit targets are provided), and manages process exit codes.
- **Session Coordination:** Coordinates validation across multiple targets, manages execution flags (such as fast-fail and output verbosity), and oversees the lifecycle of automated fixes and baseline generation.
- **Reporter Delegation:** Delegates diagnostic formatting and emission to the [Reporter hierarchy](../../lib/src/reporters/) based on the configured output format.

### 2. [Configuration & Resolution Engine](../../lib/src/config_parser.dart)
Responsible for loading, validating, resolving, and serializing user settings across different scopes.
- **Schema & Target Parsing:** Ingests repository configuration from disk or in-memory sources, parsing global rule definitions along with directory-level and skill-level overrides.
- **Hierarchical Precedence:** Resolves effective rule sets and parameter values deterministically by layering scopes: CLI overrides take highest precedence, followed by path-specific target configurations, global repository configurations, and built-in defaults.
- **Bidirectional Serialization:** Supports programmatic serialization and deserialization, enabling automated tooling, test harnesses, and migration workflows to generate and transform configuration definitions with lossless round-trip fidelity.

### 3. [Stateless Validation Engine](../../lib/src/validator.dart)
The core analysis engine responsible for inspecting individual skills.
- **Context Extraction:** Ingests skill directories, parses metadata frontmatter and Markdown content into structured representations, and captures low-level parsing or syntax errors.
- **Rule Dispatch:** Iterates over the active rules for a given skill context and aggregates emitted diagnostic results.
- **Purity & Isolation:** Operates as a pure analysis unit without side effects, remaining entirely decoupled from CLI arguments, terminal I/O, or session orchestration.

### 4. [Rule Subsystem & Extensibility](../../lib/src/rules/)
The extensible framework for authoring and running skill checks.
- **Diagnostic Rules:** Independent rule checkers that validate specific constraints (such as metadata schemas, directory layout, path portability, and naming conventions).
- **Auto-Fix Interface:** Rules that support automated remediation define pure transformation operations, taking current file content and returning modified content without directly touching the filesystem.

### 5. [Baseline & Suppression Subsystem](../../lib/src/skills_ignores_storage.dart)
The persistent suppression mechanism enabling incremental adoption and baseline suppression management.
- **Structured Suppressions:** Stores and matches ignored diagnostics using structured identifiers and file paths rather than brittle free-form string matching.
- **Lifecycle Tracking:** Records generated baseline entries when requested and tracks active suppression usage during lint runs to report stale or obsolete entries.

### 6. [Reporter Subsystem](../../lib/src/reporters/)
The multi-format output streaming subsystem.
- **Polymorphic Reporting:** Dispatches session lifecycle events (`onDirectoryEvaluating`, `onSkillEvaluating`, `onSkillValidationComplete`, `onFixApplied`, `onSessionComplete`) across output formats (`TextReporter`, `JsonReporter`, `SarifReporter`).
- **Standardized Output Channels:** Ensures clean channel separation—structured documents (JSON, SARIF) stream to stdout while operational diagnostics and errors stream to stderr.

---

## ⏳ Execution Lifecycle

The high-level lifecycle follows a staged pipeline:

```mermaid
sequenceDiagram
    autonumber
    participant CLI as CLI & Orchestrator
    participant Config as Config Engine
    participant Engine as Validation Engine
    participant Rules as Rule Subsystem
    participant Baseline as Baseline Subsystem
    participant Reporter as Reporter Subsystem

    CLI->>Config: Load and resolve configuration
    Config-->>CLI: Effective configuration & target definitions
    
    loop For each Skill Target
        CLI->>Reporter: onDirectoryEvaluating / onSkillEvaluating
        CLI->>Baseline: Load baseline suppressions
        CLI->>Engine: Run validation for skill target
        Engine->>Rules: Execute active rules against skill context
        Rules-->>Engine: Raw diagnostic violations
        Engine-->>CLI: Validation results
        CLI->>Baseline: Apply suppressions & track rule usage
        CLI->>Reporter: onSkillValidationComplete
        
        alt Fix Mode Enabled
            CLI->>Rules: Compute proposed fixes in memory
            Rules-->>CLI: Transformed content
            alt Dry Run
                CLI->>Reporter: onDryRunProposed
            else Apply
                CLI->>CLI: Write updated files to disk
                CLI->>Reporter: onFixApplied
                CLI->>Engine: Re-validate to verify fix correctness
            end
        end
    end

    alt Baseline Generation Mode
        CLI->>Baseline: Persist unsuppressed violations to baseline file
    end

    CLI->>Reporter: onSessionComplete
    CLI->>CLI: Determine process exit code
```

---

## 🧠 Durable Design Patterns

1. **Separation of Validation from Orchestration**  
   The validation engine and individual rules are pure, deterministic functions of a skill's filesystem state. They never interact with terminal streams, environment variables, or process lifecycles. All output formatting, fix persistence, diff rendering, and exit code determination belong exclusively to the orchestrator and reporter subsystems.

2. **Deterministic Layered Inheritance**  
   Configuration settings and rule parameters merge cleanly across scopes. Narrower scopes (e.g., target-specific settings or CLI flags) override broader defaults without unintentionally resetting unrelated sibling parameters.

3. **Two-Phase Fix & Verification Lifecycle**  
   Remediation is always split into two distinct phases: in-memory transformation and subsequent re-validation. Rules produce candidate fixes as data rather than performing disk writes. When fixes are applied, the orchestrator immediately re-validates the target to ensure the fix resolved the error without introducing regressions.

4. **Structured Baseline Auditing**  
   Suppression baselines rely on stable rule identifiers and relative file paths rather than fragile log message matching. Baselines are actively audited during execution to identify stale suppressions when violations are fixed.

5. **Typesafe Bidirectional Configuration Lifecycle**  
   Configuration state supports deterministic round-trip serialization between structured in-memory representations and valid YAML documents. Serialized definitions conform strictly to standard schema keys and preserve type semantics (including booleans, numerics, and explicit null resets) across parse and emission cycles.

6. **Class Constants for Serialization and Schema Keys**  
   Schema, serialization, YAML, and configuration keys are declared as static class constants co-located on their owning data models rather than inline string literals. Centralizing property keys ensures a single source of truth for wire representations and causes downstream key renames to fail at compile time.

7. **Single-Anchor Path Canonicalization at the Boundary**  
   A relative path is resolved exactly once, at the point where it enters the tool, and the anchor is determined by how the path arrived rather than by who consumes it. Paths written inside a configuration file anchor to the directory holding that configuration file; paths supplied as CLI arguments or public API arguments anchor to the current working directory. A configuration file therefore means the same thing whether it was auto-discovered or named explicitly with `--config`, and reading the file is sufficient to know what it selects. Only three call sites may canonicalize — [`ConfigParser`](../../lib/src/config_parser.dart), `validateSkillsInternal` in [`entry_point.dart`](../../lib/src/entry_point.dart), and [`ValidationSession`](../../lib/src/validation_session.dart) — so every layer beneath them can assume it already holds an absolute path. [`test/path_boundary_test.dart`](../../test/path_boundary_test.dart) fails when a fourth call site appears.

---

## 🚫 Rejected Architectural Anti-Patterns

The following patterns have been explicitly rejected in this codebase:

- **Leaking CLI or Process State into Rules:** Rules must never inspect command-line arguments, environment variables, or global process state. All required context and configuration must be passed via structured context and parameter objects.
- **In-Place File Mutations Inside Rules:** Rules must never perform raw disk writes, delete files, or execute subprocesses during validation. Auto-fixing rules must return proposed modifications to the orchestrator.
- **Brittle Message Matching for Suppressions:** Never match error messages or log text to filter suppressions. Suppressions must always use structured rule IDs and file boundaries.
- **Platform-Dependent Path Handling:** Hardcoded path separators (such as `/` or `\`) or assumptions about POSIX shell behavior break Windows compatibility. All path operations must use platform-agnostic path utilities (`package:path`).
- **Non-Dart Tooling & Scripts:** Introducing Python, shell, or JavaScript scripts for test harnesses, evaluation fixtures, or developer automation violates the repository-wide Dart-only policy. All automation and tooling must be authored in Dart.
- **Inventing Spec URLs for Non-Spec Rules:** Rules must never invent, assume, or attach URLs referencing the Agent Skills specification unless the rule directly enforces a requirement explicitly specified in the official specification document. Opt-in rules, internal invariants, and repository-specific conventions must not cite the spec.
