# Environment Model Discovery Guide

This guide details supported, environment-specific methods to verify the active model, effort level, and runtime configuration during evaluation runs using Dart.

The complete, statically analyzed, and documented discovery runner is implemented in [`../scripts/discover_environment_model.dart`](../scripts/discover_environment_model.dart).

---

## 🚀 Running Model Discovery

To execute discovery and output the active model and reasoning effort in JSON format:

```bash
# Run for the active session (reads $ANTIGRAVITY_CONVERSATION_ID)
dart run .agents/skills/run-evals/scripts/discover_environment_model.dart

# Run for a specific conversation ID
dart run .agents/skills/run-evals/scripts/discover_environment_model.dart <conversation_id>
```

---

## 🧩 Strategy-Based Discovery Architecture

Model discovery is architected around the `ModelDiscoveryStrategy` pipeline in [`../scripts/discover_environment_model.dart`](../scripts/discover_environment_model.dart), allowing new execution harnesses and runtime providers to be added seamlessly.

### Built-in Discovery Strategies

1. **Jetski Global State Database (`JetskiGlobalStateStrategy`)**:
   - Inspects the IDE SQLite database (`state.vscdb`) at platform-specific paths (macOS, Linux, Windows).
   - Reads the active model ID from `antigravityUnifiedStateSync.modelPreferences` and resolves full display names, slugs, and effort levels from `antigravityUnifiedStateSync.userStatus`.
2. **Conversation Generation Metadata (`JetskiConversationDbStrategy`)**:
   - Inspects the active session's SQLite database (`~/.gemini/jetski/conversations/<id>.db`).
   - Reads the latest generation metadata payload from table `gen_metadata` to extract runtime model slugs and enum tokens.
3. **Environment Variables (`EnvironmentVariableStrategy`)**:
   - Checks well-known environment variables (e.g., `ANTIGRAVITY_MODEL`, `GEMINI_MODEL`, `LLM_MODEL`).

> [!NOTE]
> Detailed byte offset parsing, protobuf varint decoding (LEB128), and database query implementations are fully encapsulated and documented with DartDocs directly in [`../scripts/discover_environment_model.dart`](../scripts/discover_environment_model.dart).

---

## 🛡️ Unverified Fallback Policy

If the environment databases are inaccessible, locked, or running in an unsupported runtime harness:
- Do **NOT** guess or assume the model name or effort level.
- Record the field as `Active session model (unspecified)`. Do **NOT** omit the field.
