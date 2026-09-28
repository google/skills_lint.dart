// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// Where a configuration target was declared.
///
/// Diagnostics about a target that does not exist use this to show the path
/// as the author wrote it, where they wrote it, and what it was resolved
/// against. Internal to skills_lint: it is not exported from the public
/// library.
@immutable
class TargetDeclaration {
  const TargetDeclaration({required this.declaredPath, required this.anchorDirectory, this.source});

  /// The target path exactly as written in the configuration.
  final String declaredPath;

  /// The absolute directory that a relative [declaredPath] resolved against.
  final String anchorDirectory;

  /// The absolute path of the configuration file and the 1-based line of
  /// [declaredPath] in it, or `null` for configuration content that did not
  /// come from a file.
  final ({String file, int line})? source;
}
