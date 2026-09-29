// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Constants shared by the SARIF 2.1.0 models and the regions they carry.
abstract final class SarifConstants {
  /// Assertion message for a region whose `startLine` is below 1.
  static const String invalidStartLineMessage = 'SARIF 2.1.0 requires startLine >= 1';
}
