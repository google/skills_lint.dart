// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'sarif_result.dart';
import 'sarif_tool.dart';

/// Represents a single static analysis run in a SARIF log.
class SarifRun {
  SarifRun({required this.tool, this.results = const [], this.originalUriBaseIds});

  /// Constructs a [SarifRun] from a JSON map.
  factory SarifRun.fromJson(Map<String, Object?> json) {
    return SarifRun(
      tool: SarifTool.fromJson(json[keyTool]! as Map<String, Object?>),
      results:
          (json[keyResults] as List<Object?>?)
              ?.map((r) => SarifResult.fromJson(r! as Map<String, Object?>))
              .toList() ??
          [],
      originalUriBaseIds: json[keyOriginalUriBaseIds] as Map<String, Object?>?,
    );
  }

  /// JSON key for [tool].
  static const String keyTool = 'tool';

  /// JSON key for [results].
  static const String keyResults = 'results';

  /// JSON key for [originalUriBaseIds].
  static const String keyOriginalUriBaseIds = 'originalUriBaseIds';

  /// Information about the tool that performed the analysis.
  final SarifTool tool;

  /// The set of analysis results produced by the run.
  final List<SarifResult> results;

  /// Specifies the original absolute URIs associated with the uriBaseId values.
  final Map<String, Object?>? originalUriBaseIds;

  /// Converts this run to a JSON map.
  Map<String, Object?> toJson() => {
    keyTool: tool.toJson(),
    if (originalUriBaseIds != null) keyOriginalUriBaseIds: originalUriBaseIds,
    keyResults: results.map((r) => r.toJson()).toList(),
  };
}
