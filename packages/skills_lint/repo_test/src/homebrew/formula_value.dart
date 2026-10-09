// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The comment that marks each formula line whose value is a placeholder.
const String placeholderMarker = '# PLACEHOLDER';

/// A value from the formula, with its 1-based line so that a violation can
/// point at it, and whether that line has [placeholderMarker].
typedef FormulaValue = ({String value, int line, bool placeholder});
