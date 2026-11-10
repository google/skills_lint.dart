// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'sarif_notification.dart';

/// One run of the analysis tool: whether it succeeded, and what it reported
/// about its own configuration.
@immutable
class SarifInvocation {
  const SarifInvocation({
    required this.executionSuccessful,
    this.toolConfigurationNotifications = const [],
  });

  /// Constructs a [SarifInvocation] from a JSON map.
  factory SarifInvocation.fromJson(Map<String, Object?> json) {
    return SarifInvocation(
      executionSuccessful: json[keyExecutionSuccessful]! as bool,
      toolConfigurationNotifications:
          (json[keyToolConfigurationNotifications] as List<Object?>?)
              ?.map((n) => SarifNotification.fromJson(n! as Map<String, Object?>))
              .toList() ??
          [],
    );
  }

  /// JSON key for [executionSuccessful].
  static const String keyExecutionSuccessful = 'executionSuccessful';

  /// JSON key for [toolConfigurationNotifications].
  static const String keyToolConfigurationNotifications = 'toolConfigurationNotifications';

  /// Whether the tool ran to completion. Findings in the results do not make
  /// this `false`.
  final bool executionSuccessful;

  /// Problems with the tool's configuration.
  final List<SarifNotification> toolConfigurationNotifications;

  /// Converts this invocation to a JSON map.
  Map<String, Object?> toJson() => {
    keyExecutionSuccessful: executionSuccessful,
    if (toolConfigurationNotifications.isNotEmpty)
      keyToolConfigurationNotifications: toolConfigurationNotifications
          .map((n) => n.toJson())
          .toList(),
  };
}
