# Environment Model Discovery Guide

This guide details supported, environment-specific methods to verify the active model, effort level, and runtime configuration during evaluation runs using Dart.

The complete, statically analyzed and formatted discovery script is implemented in [`tool/discover_environment_model.dart`](../../../../tool/discover_environment_model.dart).

---

## 🚀 Running Model Discovery

To inspect and output the active model and effort level in JSON format:

```bash
# Run for the active session (reads $ANTIGRAVITY_CONVERSATION_ID)
dart run tool/discover_environment_model.dart

# Run for a specific conversation ID
dart run tool/discover_environment_model.dart <conversation_id>
```

---

## 1. Conversation Generation Metadata DB (Per-Session Direct Source)

Each active agent session stores turn-by-turn generation metadata in a local conversation SQLite database.

- **Database Path**: `~/.gemini/jetski/conversations/<conversation_id>.db`
  *(where `<conversation_id>` is `$ANTIGRAVITY_CONVERSATION_ID` or passed explicitly)*

- **Schema**: Table `gen_metadata(idx integer, data blob, size integer, PRIMARY KEY(idx))`

- **Resolution**:
  1. Query the latest row: `SELECT hex(data) FROM gen_metadata ORDER BY idx DESC LIMIT 1`.
  2. Extract the model slug (e.g. `gemini-3.7-flash-high`) or `model_enum` (e.g. `MODEL_PLACEHOLDER_M298`).
  3. Implemented in function `getConversationModel` in [`tool/discover_environment_model.dart`](../../../../tool/discover_environment_model.dart).

---

## 2. VS Code / Jetski Global State DB (Full Catalog & Display Names)

When running inside VS Code / Jetski, the active UI model selection and full model registry are synchronized in the global state SQLite database.

- **Database Path**:
  - **macOS**: `~/Library/Application Support/Jetski/User/globalStorage/state.vscdb`
  - **Linux**: `~/.config/Jetski/User/globalStorage/state.vscdb`
  - **Windows**: `%APPDATA%\Jetski\User\globalStorage\state.vscdb`

- **Resolution**:
  1. Read the user active model preference from key `antigravityUnifiedStateSync.modelPreferences` (`last_selected_agent_model_sentinel_key`) and decode the base64/protobuf payload to extract the active integer model ID (e.g., `1298`).
  2. Query `antigravityUnifiedStateSync.userStatus` to resolve the model ID against the registered model catalog to obtain:
     - **Display Name**: (e.g., `Gemini 3.7 Flash (High)`)
     - **Effort Level**: (e.g., `High`, `Medium`, `Low`, or `Standard`)
     - **Model Slug**: (e.g., `gemini-3.7-flash-high`)
  3. Implemented in function `getGlobalStateModel` in [`tool/discover_environment_model.dart`](../../../../tool/discover_environment_model.dart).

---

## 3. Unverified Fallback Policy

If the environment database is inaccessible, locked, or running in an unsupported runtime harness:
- Do **NOT** guess or assume the model name or effort level.
- Record the field as `Active session model (unspecified)` or omit the field entirely from the evaluation results.
