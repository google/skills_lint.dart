// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Represents verified metadata for an AI model discovered in the active runtime.
class DiscoveredModelInfo {
  const DiscoveredModelInfo({
    required this.strategyName,
    this.modelName,
    this.modelSlug,
    this.effortLevel,
    this.attributes = const <String, dynamic>{},
  });

  /// The name of the discovery strategy that identified this model.
  final String strategyName;

  /// The human-readable display name of the model in the format
  /// '<Model Family> <Version> <Tier> (<Effort>)', such as
  /// 'Gemini 3.7 Flash (High)'.
  final String? modelName;

  /// The machine-readable hyphen-separated model identifier, such as
  /// 'gemini-3.7-flash-high'.
  final String? modelSlug;

  /// The configured reasoning effort level ('low', 'medium', or 'high').
  final String? effortLevel;

  /// Additional diagnostic attributes extracted during discovery.
  final Map<String, dynamic> attributes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'strategy': strategyName,
        if (modelName != null) 'name': modelName,
        if (modelSlug != null) 'slug': modelSlug,
        if (effortLevel != null) 'effort_level': effortLevel,
        if (attributes.isNotEmpty) 'attributes': attributes,
      };
}

/// Execution context passed to model discovery strategies.
class DiscoveryContext {
  const DiscoveryContext({
    this.conversationId,
    this.customDatabasePath,
    Map<String, String>? environment,
  }) : environment = environment ?? Platform.environment;

  /// The unique conversation identifier for the active session, if available.
  final String? conversationId;

  /// An optional override path to the IDE or session database file.
  final String? customDatabasePath;

  /// The environment variable map (defaults to [Platform.environment]).
  final Map<String, String> environment;

  /// Resolves the home directory across macOS, Linux, and Windows.
  String? get homeDirectory =>
      environment['HOME'] ?? environment['USERPROFILE'];
}

/// Contract for environment model discovery strategies.
///
/// Implementations for IDE state databases, conversation metadata, or
/// environment variables implement this interface to plug into the
/// [EnvironmentModelDiscovery] pipeline.
abstract interface class ModelDiscoveryStrategy {
  /// Unique, human-readable name of this discovery strategy.
  String get name;

  /// A brief description of the mechanism and data source used.
  String get description;

  /// Executes model discovery against the provided [context].
  ///
  /// Returns a [DiscoveredModelInfo] if a model was identified, or `null` if
  /// the data source was unavailable, empty, or unparseable.
  Future<DiscoveredModelInfo?> discover(DiscoveryContext context);
}

/// Discovers the active model from the IDE (Jetski / VS Code) global state database.
///
/// ### Storage Mechanics
/// Jetski stores workspace and global state in an SQLite database located at:
/// - macOS: `~/Library/Application Support/Jetski/User/globalStorage/state.vscdb`
/// - Linux: `~/.config/Jetski/User/globalStorage/state.vscdb`
/// - Windows: `%APPDATA%\Jetski\User\globalStorage\state.vscdb`
///
/// The database contains key-value entries in table `ItemTable`:
/// 1. `antigravityUnifiedStateSync.modelPreferences`: Contains a base64-encoded
///    protobuf message. Inside, the field `last_selected_agent_model_sentinel_key`
///    holds a varint-encoded integer representing the currently selected model ID.
/// 2. `antigravityUnifiedStateSync.userStatus`: Contains the full model catalog
///    with display names, slugs, and ID mappings.
class JetskiGlobalStateStrategy implements ModelDiscoveryStrategy {
  const JetskiGlobalStateStrategy();

  @override
  String get name => 'Jetski Global State Database';

  @override
  String get description =>
      'Extracts selected model ID and catalog details from the IDE SQLite state database';

  @override
  Future<DiscoveredModelInfo?> discover(DiscoveryContext context) async {
    final dbPath = context.customDatabasePath ?? _resolveDefaultDbPath(context);
    if (dbPath == null || !File(dbPath).existsSync()) {
      return null;
    }

    // Step 1: Query the user's active model preference.
    final selectedModelId = await _readSelectedModelId(dbPath);
    if (selectedModelId == null) {
      return null;
    }

    // Step 2: Query the user status catalog to map model ID to name and slug.
    final catalogEntry = await _lookupModelCatalog(dbPath, selectedModelId);

    return DiscoveredModelInfo(
      strategyName: name,
      modelName: catalogEntry?.name,
      modelSlug: catalogEntry?.slug,
      effortLevel: _inferEffortLevel(catalogEntry?.name, catalogEntry?.slug),
      attributes: <String, dynamic>{
        'database_path': dbPath,
        'selected_model_id': selectedModelId,
      },
    );
  }

  /// Locates the platform-specific default path to `state.vscdb`.
  String? _resolveDefaultDbPath(DiscoveryContext context) {
    final home = context.homeDirectory;
    if (home == null) return null;

    if (Platform.isMacOS) {
      return '$home/Library/Application Support/Jetski/User/globalStorage/state.vscdb';
    } else if (Platform.isLinux) {
      return '$home/.config/Jetski/User/globalStorage/state.vscdb';
    } else if (Platform.isWindows) {
      final appData = context.environment['APPDATA'] ?? '';
      return '$appData\\Jetski\\User\\globalStorage\\state.vscdb';
    }
    return null;
  }

  /// Reads the active model ID from `antigravityUnifiedStateSync.modelPreferences`.
  Future<int?> _readSelectedModelId(String dbPath) async {
    final res = await Process.run('sqlite3', <String>[
      dbPath,
      "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.modelPreferences';",
    ]);
    if (res.exitCode != 0 || res.stdout.toString().trim().isEmpty) {
      return null;
    }

    try {
      final rawBase64 = res.stdout.toString().trim();
      final Uint8List protoBytes = base64.decode(rawBase64);
      final textPrefs = latin1.decode(protoBytes);

      // Matches the protobuf field header for `last_selected_agent_model_sentinel_key`:
      // - Field tag: 'last_selected_agent_model_sentinel_key'
      // - Wire tag 0x12: Field #2 (wire type 2: length-delimited envelope)
      // - Varint length: [\x80-\xff]*[\x00-\x7f] (LEB128 varint)
      // - Wire tag 0x0A (\n): Field #1 (wire type 2: length-delimited string)
      // - Varint length: [\x80-\xff]*[\x00-\x7f] (LEB128 payload length)
      // - Group 1: Base64-encoded inner protobuf data ([A-Za-z0-9+/=]+)
      const varintPattern = r'[\x80-\xff]*[\x00-\x7f]';
      final modelPrefsPattern = RegExp(
        'last_selected_agent_model_sentinel_key'
        r'\x12' // Wire tag 0x12 (length-delimited envelope)
        '$varintPattern' // Envelope length prefix
        r'\n' // Wire tag 0x0A (string payload)
        '$varintPattern' // Payload length prefix
        r'([A-Za-z0-9+/=]+)', // Group 1: Base64 payload
      );

      final match = modelPrefsPattern.firstMatch(textPrefs);
      if (match == null) return null;

      final Uint8List payloadBytes = base64.decode(match.group(1)!);
      return _decodeVarint(payloadBytes, offset: 1);
    } catch (_) {
      return null;
    }
  }

  /// Looks up model name and slug in `antigravityUnifiedStateSync.userStatus`.
  Future<({String? name, String? slug})?> _lookupModelCatalog(
    String dbPath,
    int targetId,
  ) async {
    final res = await Process.run('sqlite3', <String>[
      dbPath,
      "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus';",
    ]);
    if (res.exitCode != 0 || res.stdout.toString().trim().isEmpty) {
      return null;
    }

    try {
      final rawBase64 = res.stdout.toString().trim();
      final Uint8List protoBytes = base64.decode(rawBase64);
      final textStatus = latin1.decode(protoBytes);

      // Matches the protobuf field header for `userStatusSentinelKey`:
      // - Field tag: 'userStatusSentinelKey'
      // - Wire tag 0x12: Field #2 (wire type 2: length-delimited envelope)
      // - Varint length: [\x80-\xff]*[\x00-\x7f]
      // - Wire tag 0x0A (\n): Field #1 (wire type 2: string payload)
      // - Varint length: [\x80-\xff]*[\x00-\x7f]
      // - Group 1: Base64-encoded inner status data ([A-Za-z0-9+/=]+)
      const varintPattern = r'[\x80-\xff]*[\x00-\x7f]';
      final statusPayloadPattern = RegExp(
        'userStatusSentinelKey'
        r'\x12' // Wire tag 0x12 (length-delimited envelope)
        '$varintPattern' // Envelope length prefix
        r'\n' // Wire tag 0x0A (string payload)
        '$varintPattern' // Payload length prefix
        r'([A-Za-z0-9+/=]+)', // Group 1: Base64 payload
      );

      final statusMatch = statusPayloadPattern.firstMatch(textStatus);
      if (statusMatch == null) return null;

      final Uint8List userStatusBytes = base64.decode(statusMatch.group(1)!);
      final userStatusText = latin1.decode(userStatusBytes);

      // Matches Gemini model catalog declarations in the userStatus protobuf:
      // - Wire tag 0x0A (\n): Field #1 (string display name)
      // - Byte [\x01-\xff]: Display name length prefix
      // - 'Gemini': Model family prefix
      // - Group 1: Model title/tier (such as " 3.7 Flash (High)")
      // - Bytes \x12\x03\x08: Model ID container (tag 0x12, length 3, tag 0x08 for varint)
      // - Group 2: Varint-encoded model ID bytes ([\x80-\xff]*[\x00-\x7f])
      final geminiModelEntryPattern = RegExp(
        r'\n' // Field tag 0x0A
        r'[\x01-\xff]' // Name length prefix
        r'Gemini' // Model family prefix
        r'([^\x00-\x1f]+)' // Group 1: Model title/tier
        r'\x12\x03\x08' // Model ID header
        r'([\x80-\xff]*[\x00-\x7f])', // Group 2: Varint ID bytes
      );

      // Matches standard hyphenated model slugs in adjacent bytes (such as "gemini-3.7-flash-high").
      final slugPattern = RegExp(r'(gemini-[a-z0-9\.\-]+)');

      for (final Match match
          in geminiModelEntryPattern.allMatches(userStatusText)) {
        final displayName = 'Gemini${match.group(1)}';
        final idBytes = Uint8List.fromList(match.group(2)!.codeUnits);
        final modelId = _decodeVarint(idBytes, offset: 0);

        if (modelId == targetId) {
          final searchEnd =
              (match.end + 100).clamp(0, userStatusText.length);
          final searchChunk = userStatusText.substring(match.start, searchEnd);
          final slugMatch = slugPattern.firstMatch(searchChunk);

          return (name: displayName, slug: slugMatch?.group(1));
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Decodes a variable-length integer (LEB128 / Protocol Buffers varint).
  ///
  /// Each byte contributes 7 bits of value until the most significant bit is 0.
  int? _decodeVarint(Uint8List bytes, {required int offset}) {
    var pos = offset;
    var result = 0;
    var shift = 0;

    while (pos < bytes.length) {
      final int byte = bytes[pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift >= 64) return null;
    }
    return null;
  }

  /// Infers reasoning effort level from model name or slug tokens.
  String? _inferEffortLevel(String? name, String? slug) {
    final lower = '${name ?? ''} ${slug ?? ''}'.toLowerCase();
    if (lower.contains('high')) return 'high';
    if (lower.contains('medium')) return 'medium';
    if (lower.contains('low')) return 'low';
    return null;
  }
}

/// Discovers model information from the per-session conversation SQLite database.
///
/// ### Storage Mechanics
/// Each conversation logs generation metadata payloads in:
/// `~/.gemini/jetski/conversations/<conversation_id>.db`
///
/// Table `gen_metadata(idx integer, data blob, size integer, PRIMARY KEY(idx))`
/// stores raw generation turn payloads containing model slug and enum strings.
class JetskiConversationDbStrategy implements ModelDiscoveryStrategy {
  const JetskiConversationDbStrategy();

  @override
  String get name => 'Jetski Conversation Metadata Database';

  @override
  String get description =>
      'Inspects turn-by-turn generation metadata blobs from the local conversation SQLite DB';

  @override
  Future<DiscoveredModelInfo?> discover(DiscoveryContext context) async {
    final convId = context.conversationId;
    if (convId == null || convId.isEmpty) {
      return null;
    }

    final home = context.homeDirectory;
    if (home == null) return null;

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

    try {
      final hex = res.stdout.toString().trim();
      final bytes = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      final payloadText = latin1.decode(bytes);

      // Matches standard hyphenated model slugs, such as "gemini-3.7-flash-high".
      final modelSlugPattern = RegExp(r'(gemini-[a-z0-9\.\-]+)');

      // Matches protobuf field for `model_enum`:
      // - Field identifier: 'model_enum'
      // - Wire tag 0x12: Field #2 (wire type 2: length-delimited string)
      // - Length byte: [\x01-\x7f] (1-byte length prefix)
      // - Group 1: Enum identifier token ([A-Za-z0-9_]+)
      final modelEnumPattern = RegExp(
        r'model_enum'
        r'\x12' // Wire tag 0x12 (length-delimited)
        r'[\x01-\x7f]' // String length prefix
        r'([A-Za-z0-9_]+)', // Group 1: Enum token
      );

      final slugMatch = modelSlugPattern.firstMatch(payloadText);
      final enumMatch = modelEnumPattern.firstMatch(payloadText);

      final slug = slugMatch?.group(1);
      final modelEnum = enumMatch?.group(1);

      if (slug == null && modelEnum == null) {
        return null;
      }

      return DiscoveredModelInfo(
        strategyName: name,
        modelSlug: slug,
        attributes: <String, dynamic>{
          'database_path': dbPath,
          'conversation_id': convId,
          if (modelEnum != null) 'model_enum': modelEnum,
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// Discovers model information from standard environment variables.
class EnvironmentVariableStrategy implements ModelDiscoveryStrategy {
  const EnvironmentVariableStrategy();

  @override
  String get name => 'Environment Variables';

  @override
  String get description =>
      'Checks standard environment variables in priority order: ANTIGRAVITY_MODEL, GEMINI_MODEL, LLM_MODEL, AI_MODEL';

  static const List<String> _candidateKeys = <String>[
    'ANTIGRAVITY_MODEL',
    'GEMINI_MODEL',
    'LLM_MODEL',
    'AI_MODEL',
  ];

  @override
  Future<DiscoveredModelInfo?> discover(DiscoveryContext context) async {
    for (final key in _candidateKeys) {
      final value = context.environment[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return DiscoveredModelInfo(
          strategyName: name,
          modelSlug: value,
          attributes: <String, dynamic>{'environment_variable': key},
        );
      }
    }
    return null;
  }
}

/// Orchestrates prioritized model discovery across multiple registered strategies.
class EnvironmentModelDiscovery {
  EnvironmentModelDiscovery({
    List<ModelDiscoveryStrategy>? strategies,
  }) : strategies = strategies ??
            const <ModelDiscoveryStrategy>[
              JetskiGlobalStateStrategy(),
              JetskiConversationDbStrategy(),
              EnvironmentVariableStrategy(),
            ];

  /// The registered discovery strategies in evaluation priority order.
  final List<ModelDiscoveryStrategy> strategies;

  /// Executes all discovery strategies and returns a consolidated summary report.
  Future<Map<String, dynamic>> discoverAll(DiscoveryContext context) async {
    final results = <String, dynamic>{};
    DiscoveredModelInfo? primaryResult;

    for (final strategy in strategies) {
      final result = await strategy.discover(context);
      if (result != null) {
        results[strategy.name] = result.toJson();
        primaryResult ??= result;
      }
    }

    return <String, dynamic>{
      'conversation_id': context.conversationId,
      'active_model': primaryResult != null
          ? <String, dynamic>{
              if (primaryResult.modelName != null)
                'name': primaryResult.modelName,
              if (primaryResult.modelSlug != null)
                'slug': primaryResult.modelSlug,
              if (primaryResult.effortLevel != null)
                'effort_level': primaryResult.effortLevel,
              'source': primaryResult.strategyName,
            }
          : null,
      'discovery_sources': results,
    };
  }
}

Future<void> main(List<String> args) async {
  final convId = args.isNotEmpty
      ? args.first
      : (Platform.environment['ANTIGRAVITY_CONVERSATION_ID'] ?? '');

  final context = DiscoveryContext(
    conversationId: convId.isNotEmpty ? convId : null,
  );

  final discovery = EnvironmentModelDiscovery();
  final report = await discovery.discoverAll(context);

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
