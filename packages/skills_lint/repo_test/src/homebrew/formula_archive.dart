// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'formula_value.dart';

/// The `url` and `sha256` lines that the formula gives one target, inside an
/// `on_<os>` and `on_<arch>` block pair.
final class FormulaArchive {
  FormulaArchive(this.target, this.line);

  /// `<os>-<arch>`, such as `macos-arm64`.
  final String target;

  /// The line of the first `url` or `sha256` in the block.
  final int line;

  /// A valid block has one.
  final List<FormulaValue> urls = [];

  /// A valid block has one.
  final List<FormulaValue> sha256s = [];
}
