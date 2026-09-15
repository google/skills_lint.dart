// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'sarif_driver.dart';

/// Information about the analysis tool that generated the run.
class SarifTool {
  SarifTool({required this.driver});

  /// Constructs a [SarifTool] from a JSON map.
  factory SarifTool.fromJson(Map<String, Object?> json) {
    return SarifTool(driver: SarifDriver.fromJson(json[keyDriver]! as Map<String, Object?>));
  }

  /// JSON key for [driver].
  static const String keyDriver = 'driver';

  /// The primary tool component (driver).
  final SarifDriver driver;

  /// Converts this tool to a JSON map.
  Map<String, Object?> toJson() => {keyDriver: driver.toJson()};
}
