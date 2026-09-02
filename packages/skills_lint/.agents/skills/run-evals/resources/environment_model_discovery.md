# Environment Model Discovery Guide

This guide details supported, environment-specific methods to verify the active model, effort level, and runtime configuration during evaluation runs using Dart.

---

## 1. Conversation Generation Metadata DB (Per-Session Direct Source)

Each active agent session stores turn-by-turn generation metadata in a local conversation SQLite database.

- **Database Path**: `~/.gemini/jetski/conversations/<conversation_id>.db`
  *(where `<conversation_id>` is `$ANTIGRAVITY_CONVERSATION_ID` or passed explicitly)*

- **Schema**: Table `gen_metadata(idx integer, data blob, size integer, PRIMARY KEY(idx))`

- **Resolution Steps**:
  1. Query the latest row: `SELECT hex(data) FROM gen_metadata ORDER BY idx DESC LIMIT 1`.
  2. Extract the model slug field (e.g. `gemini-3.7-flash-high`) or `model_enum` (e.g. `MODEL_PLACEHOLDER_M298`).

- **Dart Reference Snippet**:
  ```dart
  import 'dart:convert';
  import 'dart:io';

  Future<Map<String, String?>?> getConversationModel(String convId) async {
    final home = Platform.environment['HOME'] ?? '';
    final dbPath = '$home/.gemini/jetski/conversations/$convId.db';
    if (!File(dbPath).existsSync()) return null;

    final res = await Process.run('sqlite3', [
      dbPath,
      'SELECT hex(data) FROM gen_metadata ORDER BY idx DESC LIMIT 1;',
    ]);

    if (res.exitCode != 0 || res.stdout.toString().trim().isEmpty) return null;

    final hex = res.stdout.toString().trim();
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    final text = latin1.decode(bytes);

    final slugMatch = RegExp(r'(gemini-[a-z0-9\.\-]+)').firstMatch(text);
    final enumMatch = RegExp(r'model_enum\x12[\x01-\x7f]([A-Za-z0-9_]+)').firstMatch(text);

    return {
      'slug': slugMatch?.group(1),
      'model_enum': enumMatch?.group(1),
    };
  }
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

- **Dart Reference Snippet**:
  ```dart
  import 'dart:convert';
  import 'dart:io';

  Future<Map<String, dynamic>?> getGlobalStateModel(String dbPath) async {
    if (!File(dbPath).existsSync()) return null;

    final prefRes = await Process.run('sqlite3', [
      dbPath,
      "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.modelPreferences';",
    ]);
    if (prefRes.exitCode != 0 || prefRes.stdout.toString().trim().isEmpty) return null;

    final protoPrefs = base64.decode(prefRes.stdout.toString().trim());
    final textPrefs = latin1.decode(protoPrefs);
    final prefMatch = RegExp(r'last_selected_agent_model_sentinel_key\x12[\x80-\xff]*[\x00-\x7f]\n[\x80-\xff]*[\x00-\x7f]([A-Za-z0-9+/=]+)').firstMatch(textPrefs);
    if (prefMatch == null) return null;

    final selectedBytes = base64.decode(prefMatch.group(1)!);
    var pos = 1;
    var varint = 0;
    var shift = 0;
    while (pos < selectedBytes.length) {
      final b = selectedBytes[pos++];
      varint |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    final selectedId = varint;

    final statusRes = await Process.run('sqlite3', [
      dbPath,
      "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus';",
    ]);
    if (statusRes.exitCode != 0 || statusRes.stdout.toString().trim().isEmpty) {
      return {'id': selectedId};
    }

    final protoStatus = base64.decode(statusRes.stdout.toString().trim());
    final textStatus = latin1.decode(protoStatus);
    final statusMatch = RegExp(r'userStatusSentinelKey\x12[\x80-\xff]*[\x00-\x7f]\n[\x80-\xff]*[\x00-\x7f]([A-Za-z0-9+/=]+)').firstMatch(textStatus);
    if (statusMatch == null) return {'id': selectedId};

    final userStatusBytes = base64.decode(statusMatch.group(1)!);
    final userStatusText = latin1.decode(userStatusBytes);

    final modelRegex = RegExp(r'\n([\x01-\xff])Gemini([^\x00-\x1f]+)\x12\x03\x08([\x80-\xff]*[\x00-\x7f])');
    for (final m in modelRegex.allMatches(userStatusText)) {
      final name = 'Gemini${m.group(2)}';
      final idBytes = m.group(3)!.codeUnits;
      var v = 0;
      var s = 0;
      for (final b in idBytes) {
        v |= (b & 0x7f) << s;
        if ((b & 0x80) == 0) break;
        s += 7;
      }
      if (v == selectedId) {
        final matchEnd = m.end;
        final searchChunk = userStatusText.substring(m.start, (matchEnd + 100).clamp(0, userStatusText.length));
        final slugMatch = RegExp(r'(gemini-[a-z0-9\.\-]+)').firstMatch(searchChunk);
        return {
          'id': selectedId,
          'name': name,
          'slug': slugMatch?.group(1),
        };
      }
    }

    return {'id': selectedId};
  }
  ```

---

## 3. Unverified Fallback Policy

If the environment database is inaccessible, locked, or running in an unsupported runtime harness:
- Do **NOT** guess or assume the model name or effort level.
- Record the field as `Active session model (unspecified)` or omit the field entirely from the evaluation results.
