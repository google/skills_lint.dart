// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: specify_nonobvious_local_variable_types, omit_obvious_local_variable_types

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Inspects the conversation SQLite database for runtime model metadata.
Future<Map<String, String?>?> getConversationModel(String convId) async {
  final home = Platform.environment['HOME'] ?? '';
  final dbPath = '$home/.gemini/jetski/conversations/$convId.db';
  if (!File(dbPath).existsSync()) {
    return null;
  }

  final res = await Process.run('sqlite3', <String>[
    dbPath,
    'SELECT hex(data) FROM gen_metadata ORDER BY idx DESC LIMIT 1;',
  ]);

  if (res.exitCode != 0 || res.stdout.toString().trim().isEmpty) {
    return null;
  }

  final hex = res.stdout.toString().trim();
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  final text = latin1.decode(bytes);

  final slugMatch = RegExp(r'(gemini-[a-z0-9\.\-]+)').firstMatch(text);
  final enumMatch = RegExp(r'model_enum\x12[\x01-\x7f]([A-Za-z0-9_]+)').firstMatch(text);

  return <String, String?>{'slug': slugMatch?.group(1), 'model_enum': enumMatch?.group(1)};
}

/// Inspects the VS Code / Jetski global state SQLite database for model preferences.
Future<Map<String, dynamic>?> getGlobalStateModel([String? customDbPath]) async {
  final dbPath = customDbPath ?? _defaultGlobalStateDbPath();
  if (dbPath == null || !File(dbPath).existsSync()) {
    return null;
  }

  final prefRes = await Process.run('sqlite3', <String>[
    dbPath,
    "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.modelPreferences';",
  ]);
  if (prefRes.exitCode != 0 || prefRes.stdout.toString().trim().isEmpty) {
    return null;
  }

  final prefOutput = prefRes.stdout.toString().trim();
  final Uint8List protoPrefs = base64.decode(prefOutput);
  final textPrefs = latin1.decode(protoPrefs);
  final prefMatch = RegExp(
    r'last_selected_agent_model_sentinel_key\x12[\x80-\xff]*[\x00-\x7f]\n[\x80-\xff]*[\x00-\x7f]([A-Za-z0-9+/=]+)',
  ).firstMatch(textPrefs);
  if (prefMatch == null) {
    return null;
  }

  final base64Payload = prefMatch.group(1)!;
  final Uint8List selectedBytes = base64.decode(base64Payload);
  var pos = 1;
  var varint = 0;
  var shift = 0;
  while (pos < selectedBytes.length) {
    final int b = selectedBytes[pos++];
    varint |= (b & 0x7f) << shift;
    if ((b & 0x80) == 0) {
      break;
    }
    shift += 7;
  }
  final selectedId = varint;

  final statusRes = await Process.run('sqlite3', <String>[
    dbPath,
    "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus';",
  ]);
  if (statusRes.exitCode != 0 || statusRes.stdout.toString().trim().isEmpty) {
    return <String, dynamic>{'id': selectedId};
  }

  final statusOutput = statusRes.stdout.toString().trim();
  final Uint8List protoStatus = base64.decode(statusOutput);
  final textStatus = latin1.decode(protoStatus);
  final statusMatch = RegExp(
    r'userStatusSentinelKey\x12[\x80-\xff]*[\x00-\x7f]\n[\x80-\xff]*[\x00-\x7f]([A-Za-z0-9+/=]+)',
  ).firstMatch(textStatus);
  if (statusMatch == null) {
    return <String, dynamic>{'id': selectedId};
  }

  final statusPayload = statusMatch.group(1)!;
  final Uint8List userStatusBytes = base64.decode(statusPayload);
  final userStatusText = latin1.decode(userStatusBytes);

  final modelRegex = RegExp(
    r'\n([\x01-\xff])Gemini([^\x00-\x1f]+)\x12\x03\x08([\x80-\xff]*[\x00-\x7f])',
  );
  for (final Match m in modelRegex.allMatches(userStatusText)) {
    final name = 'Gemini${m.group(2)}';
    final idBytes = m.group(3)!.codeUnits;
    var v = 0;
    var s = 0;
    for (final int b in idBytes) {
      v |= (b & 0x7f) << s;
      if ((b & 0x80) == 0) {
        break;
      }
      s += 7;
    }
    if (v == selectedId) {
      final matchEnd = m.end;
      final searchChunk = userStatusText.substring(
        m.start,
        (matchEnd + 100).clamp(0, userStatusText.length),
      );
      final slugMatch = RegExp(r'(gemini-[a-z0-9\.\-]+)').firstMatch(searchChunk);
      return <String, dynamic>{'id': selectedId, 'name': name, 'slug': slugMatch?.group(1)};
    }
  }

  return <String, dynamic>{'id': selectedId};
}

String? _defaultGlobalStateDbPath() {
  final home = Platform.environment['HOME'];
  if (home == null) {
    return null;
  }

  if (Platform.isMacOS) {
    return '$home/Library/Application Support/Jetski/User/globalStorage/state.vscdb';
  } else if (Platform.isLinux) {
    return '$home/.config/Jetski/User/globalStorage/state.vscdb';
  } else if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'] ?? '';
    return '$appData\\Jetski\\User\\globalStorage\\state.vscdb';
  }
  return null;
}

Future<void> main(List<String> args) async {
  final convId = args.isNotEmpty
      ? args.first
      : (Platform.environment['ANTIGRAVITY_CONVERSATION_ID'] ?? '');

  Map<String, String?>? convModel;
  if (convId.isNotEmpty) {
    convModel = await getConversationModel(convId);
  }

  final globalModel = await getGlobalStateModel();

  final output = <String, dynamic>{
    'conversation_id': convId.isNotEmpty ? convId : null,
    'conversation_metadata': convModel,
    'global_state': globalModel,
  };

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
}
