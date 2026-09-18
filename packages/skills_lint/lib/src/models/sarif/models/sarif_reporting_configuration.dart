// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// Default reporting configuration for a SARIF rule descriptor.
@immutable
class SarifReportingConfiguration {
  const SarifReportingConfiguration({required this.level});

  /// Constructs a [SarifReportingConfiguration] from a JSON map.
  factory SarifReportingConfiguration.fromJson(Map<String, Object?> json) {
    return SarifReportingConfiguration(level: (json[keyLevel] ?? 'warning') as String);
  }

  /// JSON key for [level].
  static const String keyLevel = 'level';

  /// The default severity level ('warning', 'error', 'note', 'none').
  final String level;

  /// Converts this configuration to a JSON map.
  Map<String, Object?> toJson() => {keyLevel: level};
}
