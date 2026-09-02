# Environment Model Discovery Guide

This guide details supported, environment-specific methods to verify the active model, effort level, and runtime configuration during evaluation runs.

---

## 1. Conversation Generation Metadata DB (Per-Session Direct Source)

Each active agent session stores turn-by-turn generation metadata in a local conversation SQLite database.

- **Database Path**: `~/.gemini/jetski/conversations/<conversation_id>.db`
  *(where `<conversation_id>` is `$ANTIGRAVITY_CONVERSATION_ID` or passed explicitly)*

- **Schema**: Table `gen_metadata(idx integer, data blob, size integer, PRIMARY KEY(idx))`

- **Resolution Steps**:
  1. Query the latest row: `SELECT data FROM gen_metadata ORDER BY idx DESC LIMIT 1`.
  2. Extract the model slug field (tag `\xe2\x01` or `model_enum`).
  *(Note: Avoid broad un-anchored text regexes across `data` because the blob also contains prompt context, which may include skill descriptions or user text mentioning other model names).*

- **Python Reference Snippet**:
  ```python
  import sqlite3, os, re

  def get_conversation_model(conv_id):
      db_path = os.path.expanduser(f"~/.gemini/jetski/conversations/{conv_id}.db")
      if not os.path.exists(db_path):
          return None
      cur = sqlite3.connect(db_path).cursor()
      cur.execute("SELECT data FROM gen_metadata ORDER BY idx DESC LIMIT 1")
      row = cur.fetchone()
      if not row or not row[0]:
          return None
      data = row[0]
      
      # Extract model slug (e.g. gemini-3.7-flash-high)
      m_slug = re.search(rb"\xe2\x01[\x01-\x7f]([a-zA-Z0-9\.\-_]+)", data)
      slug = m_slug.group(1).decode("ascii") if m_slug else None
      
      # Extract model enum (e.g. MODEL_PLACEHOLDER_M298)
      m_enum = re.search(rb"model_enum\x12[\x01-\x7f]([A-Za-z0-9_]+)", data)
      model_enum = m_enum.group(1).decode("ascii") if m_enum else None
      
      return {"slug": slug, "model_enum": model_enum}
  ```

---

## 2. VS Code / Jetski Global State DB (Full Catalog & Display Names)

When running inside VS Code / Jetski, the active UI model selection and full model registry are synchronized in the global state SQLite database.

- **Database Path**:
  - **macOS**: `~/Library/Application Support/Jetski/User/globalStorage/state.vscdb`
  - **Linux**: `~/.config/Jetski/User/globalStorage/state.vscdb`
  - **Windows**: `%APPDATA%\Jetski\User\globalStorage\state.vscdb`

- **Resolution Steps**:
  1. Read the user active model preference from key `antigravityUnifiedStateSync.modelPreferences` (`last_selected_agent_model_sentinel_key`) and decode the base64/protobuf payload to extract the active integer model ID (e.g., `1298`).
  2. Query `antigravityUnifiedStateSync.userStatus` to resolve the model ID against the registered model catalog to obtain:
     - **Display Name**: (e.g., `Gemini 3.7 Flash (High)`)
     - **Effort Level**: (e.g., `High`, `Medium`, `Low`, or `Standard`)
     - **Model Slug**: (e.g., `gemini-3.7-flash-high`)

- **Python Reference Snippet**:
  ```python
  import sqlite3, base64, re

  def get_active_model_from_global_state(db_path):
      conn = sqlite3.connect(db_path)
      cursor = conn.cursor()
      
      cursor.execute("SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.modelPreferences'")
      row = cursor.fetchone()
      if not row:
          return None
      proto_prefs = base64.b64decode(row[0])
      m = re.search(rb"last_selected_agent_model_sentinel_key\x12[\x80-\xff]*[\x00-\x7f]\n[\x80-\xff]*[\x00-\x7f]([A-Za-z0-9+/=]+)", proto_prefs)
      if not m:
          return None
      selected_bytes = base64.b64decode(m.group(1))
      pos, varint, shift = 1, 0, 0
      while pos < len(selected_bytes):
          b = selected_bytes[pos]
          pos += 1
          varint |= (b & 0x7f) << shift
          if not (b & 0x80):
              break
          shift += 7
      selected_id = varint

      cursor.execute("SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus'")
      row = cursor.fetchone()
      if not row:
          return {"id": selected_id}
      proto_status = base64.b64decode(row[0])
      match = re.search(rb"userStatusSentinelKey\x12[\x80-\xff]*[\x00-\x7f]\n[\x80-\xff]*[\x00-\x7f]([A-Za-z0-9+/=]+)", proto_status)
      if not match:
          return {"id": selected_id}
      user_status_bytes = base64.b64decode(match.group(1))

      for m in re.finditer(rb"\n([\x01-\xff])Gemini([^\x00-\x1f]+)\x12\x03\x08([\x80-\xff]*[\x00-\x7f])", user_status_bytes):
          name = "Gemini" + m.group(2).decode("latin1")
          id_bytes = m.group(3)
          v, s = 0, 0
          for b in id_bytes:
              v |= (b & 0x7f) << s
              if not (b & 0x80):
                  break
              s += 7
          if v == selected_id:
              chunk = user_status_bytes[m.start():min(len(user_status_bytes), m.end() + 100)]
              slug_match = re.search(rb"(gemini-[a-z0-9\.\-]+)", chunk)
              return {
                  "id": selected_id,
                  "name": name,
                  "slug": slug_match.group(1).decode("latin1") if slug_match else None
              }
      return {"id": selected_id}
  ```

---

## 3. Unverified Fallback Policy

If the environment database is inaccessible, locked, or running in an unsupported runtime harness:
- Do **NOT** guess or assume the model name or effort level.
- Record the field as `Active session model (unspecified)` or omit the field entirely from the evaluation results.
