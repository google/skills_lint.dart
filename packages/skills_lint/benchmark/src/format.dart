// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Number formatting and comparison helpers shared by the reports.
library;

/// Returns the change from [before] to [after] as a fraction of [before],
/// or `null` when either is missing or [before] is 0.
double? relativeChange(double? before, double? after) {
  if (before == null || after == null || before == 0) {
    return null;
  }
  return after / before - 1;
}

/// Formats [value] with one decimal place, or as empty when it is `null`.
String formatNumber(double? value) => value == null ? '' : value.toStringAsFixed(1);

/// Formats [fraction] as a percentage with one decimal place.
String formatPercent(double fraction) => '${(fraction * 100).toStringAsFixed(1)}%';

/// Formats [fraction] like [formatPercent], with a `+` sign when it is not
/// negative.
String formatSignedPercent(double fraction) =>
    '${fraction >= 0 ? '+' : ''}${formatPercent(fraction)}';
