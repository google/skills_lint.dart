// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'sarif_physical_location.dart';

/// A location where an analysis result was observed.
@immutable
class SarifLocation {
  const SarifLocation({required this.physicalLocation});

  /// Constructs a [SarifLocation] from a JSON map.
  factory SarifLocation.fromJson(Map<String, Object?> json) {
    return SarifLocation(
      physicalLocation: SarifPhysicalLocation.fromJson(
        json[keyPhysicalLocation]! as Map<String, Object?>,
      ),
    );
  }

  /// JSON key for [physicalLocation].
  static const String keyPhysicalLocation = 'physicalLocation';

  /// The physical artifact location and coordinate span of the finding.
  final SarifPhysicalLocation physicalLocation;

  /// Converts this location to a JSON map.
  Map<String, Object?> toJson() => {keyPhysicalLocation: physicalLocation.toJson()};
}
