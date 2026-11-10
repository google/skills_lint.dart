// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'sarif_location.dart';
import 'sarif_message.dart';

/// A condition the tool met while it ran, such as a problem in its
/// configuration, as opposed to a finding about the analyzed code.
@immutable
class SarifNotification {
  const SarifNotification({required this.level, required this.message, this.locations = const []});

  /// Constructs a [SarifNotification] from a JSON map.
  factory SarifNotification.fromJson(Map<String, Object?> json) {
    return SarifNotification(
      // SARIF §3.58.6 makes an absent level default to "warning".
      level: (json[keyLevel] ?? 'warning') as String,
      message: SarifMessage.fromJson(json[keyMessage]! as Map<String, Object?>),
      locations:
          (json[keyLocations] as List<Object?>?)
              ?.map((l) => SarifLocation.fromJson(l! as Map<String, Object?>))
              .toList() ??
          [],
    );
  }

  /// JSON key for [level].
  static const String keyLevel = 'level';

  /// JSON key for [message].
  static const String keyMessage = 'message';

  /// JSON key for [locations].
  static const String keyLocations = 'locations';

  /// Severity of the notification: `error`, `warning`, `note` or `none`.
  final String level;

  /// What the tool met.
  final SarifMessage message;

  /// Where the condition is, if anywhere.
  final List<SarifLocation> locations;

  /// Converts this notification to a JSON map.
  Map<String, Object?> toJson() => {
    keyLevel: level,
    keyMessage: message.toJson(),
    if (locations.isNotEmpty) keyLocations: locations.map((l) => l.toJson()).toList(),
  };
}
