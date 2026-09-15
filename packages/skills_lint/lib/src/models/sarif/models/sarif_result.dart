// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'sarif_location.dart';
import 'sarif_message.dart';

/// An individual diagnostic finding produced by the analysis.
class SarifResult {
  SarifResult({
    required this.ruleId,
    required this.level,
    required this.message,
    this.locations = const [],
    this.ruleIndex,
  });

  /// Constructs a [SarifResult] from a JSON map.
  factory SarifResult.fromJson(Map<String, Object?> json) {
    return SarifResult(
      ruleId: json[keyRuleId]! as String,
      level: (json[keyLevel] ?? 'warning') as String,
      message: SarifMessage.fromJson(json[keyMessage]! as Map<String, Object?>),
      locations:
          (json[keyLocations] as List<Object?>?)
              ?.map((l) => SarifLocation.fromJson(l! as Map<String, Object?>))
              .toList() ??
          [],
      ruleIndex: json[keyRuleIndex] as int?,
    );
  }

  /// JSON key for [ruleId].
  static const String keyRuleId = 'ruleId';

  /// JSON key for [level].
  static const String keyLevel = 'level';

  /// JSON key for [message].
  static const String keyMessage = 'message';

  /// JSON key for [locations].
  static const String keyLocations = 'locations';

  /// JSON key for [ruleIndex].
  static const String keyRuleIndex = 'ruleIndex';

  /// The stable identifier of the rule that produced this finding.
  final String ruleId;

  /// The severity level of this result ('warning', 'error', 'note', 'none').
  final String level;

  /// A message describing the finding.
  final SarifMessage message;

  /// The set of locations where the result was observed.
  final List<SarifLocation> locations;

  /// The zero-based index of the rule in the driver's rule catalog.
  final int? ruleIndex;

  /// Converts this result to a JSON map.
  Map<String, Object?> toJson() => {
    keyRuleId: ruleId,
    keyLevel: level,
    keyMessage: message.toJson(),
    if (locations.isNotEmpty) keyLocations: locations.map((l) => l.toJson()).toList(),
    if (ruleIndex != null) keyRuleIndex: ruleIndex,
  };
}
