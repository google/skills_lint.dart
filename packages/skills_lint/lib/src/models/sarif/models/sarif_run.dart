// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'sarif_invocation.dart';
import 'sarif_result.dart';
import 'sarif_tool.dart';

/// A static analysis run within a SARIF log.
@immutable
class SarifRun {
  const SarifRun({
    required this.tool,
    this.invocations = const [],
    this.results = const [],
    this.originalUriBaseIds,
  });

  /// Constructs a [SarifRun] from a JSON map.
  factory SarifRun.fromJson(Map<String, Object?> json) {
    return SarifRun(
      tool: SarifTool.fromJson(json[keyTool]! as Map<String, Object?>),
      invocations:
          (json[keyInvocations] as List<Object?>?)
              ?.map((i) => SarifInvocation.fromJson(i! as Map<String, Object?>))
              .toList() ??
          [],
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

  /// JSON key for [invocations].
  static const String keyInvocations = 'invocations';

  /// JSON key for [results].
  static const String keyResults = 'results';

  /// JSON key for [originalUriBaseIds].
  static const String keyOriginalUriBaseIds = 'originalUriBaseIds';

  /// The analysis tool component that executed this run.
  final SarifTool tool;

  /// The runs of the tool that produced [results].
  final List<SarifInvocation> invocations;

  /// The diagnostic findings emitted during this run.
  final List<SarifResult> results;

  /// Optional dictionary of root URI base IDs against which relative artifact URIs resolve.
  final Map<String, Object?>? originalUriBaseIds;

  /// Converts this run to a JSON map.
  Map<String, Object?> toJson() => {
    keyTool: tool.toJson(),
    if (invocations.isNotEmpty) keyInvocations: invocations.map((i) => i.toJson()).toList(),
    if (originalUriBaseIds != null) keyOriginalUriBaseIds: originalUriBaseIds,
    keyResults: results.map((r) => r.toJson()).toList(),
  };
}
