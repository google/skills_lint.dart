// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Thrown when validation was asked to run without any skills to validate.
///
/// Raised by `validateSkills` when the caller supplies no skill directories and
/// no individual skill paths, the configuration names no targets, and none of
/// the default locations exist relative to the current working directory.
///
/// Supply `skillDirPaths`, `individualSkillPaths`, or a configuration with
/// targets to avoid it.
class MissingDefaultsException implements Exception {
  /// Creates an exception reporting the [defaults] that were searched for.
  MissingDefaultsException(this.defaults);

  /// The default locations that were searched, relative to the working
  /// directory, none of which existed.
  final List<String> defaults;
}
