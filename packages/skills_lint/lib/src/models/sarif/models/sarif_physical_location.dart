// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'sarif_artifact_location.dart';
import 'sarif_region.dart';

/// The physical artifact and region coordinates of a diagnostic finding.
@immutable
class SarifPhysicalLocation {
  const SarifPhysicalLocation({required this.artifactLocation, this.region});

  /// Constructs a [SarifPhysicalLocation] from a JSON map.
  factory SarifPhysicalLocation.fromJson(Map<String, Object?> json) {
    return SarifPhysicalLocation(
      artifactLocation: SarifArtifactLocation.fromJson(
        json[keyArtifactLocation]! as Map<String, Object?>,
      ),
      region: json[keyRegion] != null
          ? SarifRegion.fromJson(json[keyRegion]! as Map<String, Object?>)
          : null,
    );
  }

  /// JSON key for [artifactLocation].
  static const String keyArtifactLocation = 'artifactLocation';

  /// JSON key for [region].
  static const String keyRegion = 'region';

  /// The file or artifact where the finding was detected.
  final SarifArtifactLocation artifactLocation;

  /// The specific coordinate span within the artifact.
  ///
  /// When `null`, the finding applies to the entire artifact.
  final SarifRegion? region;

  /// Converts this physical location to a JSON map.
  Map<String, Object?> toJson() => {
    keyArtifactLocation: artifactLocation.toJson(),
    if (region != null) keyRegion: region!.toJson(),
  };
}
