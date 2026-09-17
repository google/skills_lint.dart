// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'sarif_run.dart';

/// Top-level SARIF 2.1.0 log document.
///
/// Example JSON structure:
/// ```json
/// {
///   "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json",
///   "version": "2.1.0",
///   "runs": [
///     {
///       "tool": {
///         "driver": {
///           "name": "skills_lint",
///           "informationUri": "https://github.com/google/skills_lint.dart",
///           "rules": []
///         }
///       },
///       "results": []
///     }
///   ]
/// }
/// ```
class SarifLog {
  SarifLog({this.schema = schemaUri, this.version = specVersion, required this.runs});

  /// Constructs a [SarifLog] from a JSON map.
  factory SarifLog.fromJson(Map<String, Object?> json) {
    final version = (json[keyVersion] ?? specVersion) as String;
    if (version != specVersion) {
      throw FormatException('Unsupported SARIF version: $version (expected $specVersion)');
    }
    return SarifLog(
      schema: (json[keySchema] ?? json['schema'] ?? schemaUri) as String,
      version: version,
      runs:
          (json[keyRuns] as List<Object?>?)
              ?.map((r) => SarifRun.fromJson(r! as Map<String, Object?>))
              .toList() ??
          [],
    );
  }

  /// JSON key for [schema].
  static const String keySchema = r'$schema';

  /// JSON key for [version].
  static const String keyVersion = 'version';

  /// JSON key for [runs].
  static const String keyRuns = 'runs';

  /// The canonical, immutable OASIS-hosted schema URI for SARIF 2.1.0 errata01.
  static const String schemaUri =
      'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json';

  /// The only `version` string permitted by SARIF 2.1.0 (OASIS spec §3.13.2).
  static const String specVersion = '2.1.0';

  /// The URI of the SARIF JSON schema.
  final String schema;

  /// The format version (always '2.1.0').
  final String version;

  /// The set of analysis runs contained in this log.
  final List<SarifRun> runs;

  /// Converts this SARIF log to a JSON map.
  Map<String, Object?> toJson() => {
    keySchema: schema,
    keyVersion: version,
    keyRuns: runs.map((r) => r.toJson()).toList(),
  };
}
