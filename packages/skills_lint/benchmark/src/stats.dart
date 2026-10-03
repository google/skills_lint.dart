// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Summary statistics for benchmark samples.
library;

import 'package:meta/meta.dart';

/// Order statistics of a non-empty list of samples.
///
/// The benchmarks judge changes by the [median], which a few slow runs on a
/// busy machine do not move. [madPercent] shows how much the runs spread.
@immutable
final class Summary {
  /// Computes the summary of [samples].
  ///
  /// Throws [ArgumentError] if [samples] is empty.
  factory Summary.of(List<num> samples) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'must not be empty');
    }
    final List<double> sorted = [for (final s in samples) s.toDouble()]..sort();
    final double median = _median(sorted);
    final List<double> deviations = [for (final s in sorted) (s - median).abs()]..sort();
    return Summary._(
      count: sorted.length,
      min: sorted.first,
      median: median,
      p90: percentile(sorted, 90),
      max: sorted.last,
      mad: _median(deviations),
    );
  }

  const Summary._({
    required this.count,
    required this.min,
    required this.median,
    required this.p90,
    required this.max,
    required this.mad,
  });

  /// Number of samples.
  final int count;

  /// Smallest sample.
  final double min;

  /// Middle sample, or the mean of the two middle samples when [count] is
  /// even.
  final double median;

  /// 90th percentile by the nearest-rank method.
  final double p90;

  /// Largest sample.
  final double max;

  /// Median absolute deviation from [median], in the samples' unit.
  final double mad;

  /// [mad] as a percentage of [median], or 0 when [median] is 0.
  double get madPercent => median == 0 ? 0 : mad / median * 100;
}

/// Returns the [percent]th percentile of [sorted] by the nearest-rank
/// method: the smallest sample that is at least [percent]% of the samples.
///
/// [sorted] must be non-empty and sorted in ascending order, and [percent]
/// must be in the range (0, 100].
double percentile(List<double> sorted, num percent) {
  if (sorted.isEmpty) {
    throw ArgumentError.value(sorted, 'sorted', 'must not be empty');
  }
  if (percent <= 0 || percent > 100) {
    throw RangeError.range(percent, 0, 100, 'percent');
  }
  final int rank = (percent / 100 * sorted.length).ceil();
  return sorted[rank - 1];
}

double _median(List<double> sorted) {
  final int middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
