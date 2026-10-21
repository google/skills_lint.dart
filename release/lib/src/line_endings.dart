// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The line terminators other than `\n`.
///
/// These are `\r\n`, and the lone `\r` of classic Mac OS.
final RegExp _nonLfLineTerminator = RegExp(r'\r\n?');

/// Line-ending normalization for text read from a checkout.
extension NormalizeLineTerminators on String {
  /// This string with every `\r\n` and lone `\r` replaced by `\n`.
  ///
  /// A Windows checkout can give text files CRLF line endings.
  String normalizeLineTerminators() => replaceAll(_nonLfLineTerminator, '\n');
}
