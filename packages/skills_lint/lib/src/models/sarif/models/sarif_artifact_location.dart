// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Identifies an artifact (file) by URI.
class SarifArtifactLocation {
  SarifArtifactLocation({required this.uri, this.uriBaseId});

  /// Constructs a [SarifArtifactLocation] from a JSON map.
  factory SarifArtifactLocation.fromJson(Map<String, Object?> json) {
    return SarifArtifactLocation(
      uri: json[keyUri]! as String,
      uriBaseId: json[keyUriBaseId] as String?,
    );
  }

  /// JSON key for [uri].
  static const String keyUri = 'uri';

  /// JSON key for [uriBaseId].
  static const String keyUriBaseId = 'uriBaseId';

  /// A string containing a valid, relative or absolute URI.
  final String uri;

  /// A string that identifies the URI base identifier against which [uri] is relative.
  final String? uriBaseId;

  /// Converts this artifact location to a JSON map.
  Map<String, Object?> toJson() => {keyUri: uri, if (uriBaseId != null) keyUriBaseId: uriBaseId};
}
