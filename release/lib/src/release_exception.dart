// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Thrown when a release step can't finish. The `release` command prints
/// [message] and exits with code 1.
class ReleaseException implements Exception {
  ReleaseException(this.message);

  final String message;
}
