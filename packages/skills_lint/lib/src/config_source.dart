// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// Identifies where configuration content came from for path resolution and diagnostics.
@immutable
class ConfigSource {
  /// Uses [path] as the configuration file name and anchors paths to its directory.
  const ConfigSource.file(String path) : filePath = path, directoryPath = null;

  /// Anchors paths to [path] when the configuration has no backing file.
  const ConfigSource.directory(String path) : filePath = null, directoryPath = path;

  /// The configuration file used for diagnostics and path anchoring, or null for in-memory content.
  final String? filePath;

  /// The directory used to anchor in-memory content, or null for a file source.
  final String? directoryPath;
}
