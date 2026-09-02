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

### Example Output

```json
{
  "conversation_id": "627fed6a-adfe-4c00-b62f-6ac832a6d573",
  "active_model": {
    "name": "Gemini 3.7 Flash (High)",
    "slug": "gemini-3.7-flash-high",
    "effort_level": "high",
    "source": "Jetski Global State Database"
  },
  "discovery_sources": {
    "Jetski Global State Database": {
      "strategy": "Jetski Global State Database",
      "name": "Gemini 3.7 Flash (High)",
      "slug": "gemini-3.7-flash-high",
      "effort_level": "high",
      "attributes": {
        "database_path": "/Users/reidbaker/Library/Application Support/Jetski/User/globalStorage/state.vscdb",
        "selected_model_id": 1298
      }
    },
    "Jetski Conversation Metadata Database": {
      "strategy": "Jetski Conversation Metadata Database",
      "slug": "gemini-3.7-flash-high",
      "attributes": {
        "database_path": "/Users/reidbaker/.gemini/jetski/conversations/627fed6a-adfe-4c00-b62f-6ac832a6d573.db",
        "conversation_id": "627fed6a-adfe-4c00-b62f-6ac832a6d573",
        "model_enum": "MODEL_PLACEHOLDER_M298"
      }
    }
  }
}
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
   - Checks well-known environment variables (such as `ANTIGRAVITY_MODEL`, `GEMINI_MODEL`, or `LLM_MODEL`).

> [!NOTE]
> Detailed byte offset parsing, protobuf varint decoding (LEB128), and database query implementations are fully encapsulated and documented with DartDocs directly in [`../scripts/discover_environment_model.dart`](../scripts/discover_environment_model.dart).

---

## 🛡️ Unverified Fallback Policy

If the environment databases are inaccessible, locked, or running in an unsupported runtime harness:
- Do **NOT** guess or assume the model name or effort level.
- Record the field as `Active session model (unspecified)`. Do **NOT** omit the field.
