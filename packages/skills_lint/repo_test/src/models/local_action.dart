// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A local `uses: ./<path>` that names a directory, which GitHub runs as a
/// composite action.
final class LocalAction {
  LocalAction(this.source, this.line, this.value, this.directory);

  /// Path of the workflow or action file that holds the `uses:`.
  final String source;

  /// 1-based line of the `uses:` value.
  final int line;

  /// The `uses:` value as written.
  final String value;

  /// The directory the value names, joined to the repository root.
  final String directory;
}
