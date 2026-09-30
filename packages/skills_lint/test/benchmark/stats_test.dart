// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../benchmark/src/stats.dart';

void main() {
  group('Summary.of', () {
    test('summarizes an odd number of samples in any order', () {
      final summary = Summary.of(const [5, 1, 4, 2, 3]);

      expect(summary.count, 5);
      expect(summary.min, 1);
      expect(summary.median, 3);
      expect(summary.p90, 5);
      expect(summary.max, 5);
      // Deviations from 3 are 2, 1, 1, 0, 2; their median is 1.
      expect(summary.mad, 1);
      expect(summary.madPercent, closeTo(33.33, 0.01));
    });

    test('takes the mean of the two middle samples for an even count', () {
      final summary = Summary.of(const [10, 40, 20, 30]);

      expect(summary.median, 25);
      // Deviations from 25 are 15, 5, 5, 15; their median is 10.
      expect(summary.mad, 10);
    });

    test('ignores a single outlier in the median and MAD', () {
      final summary = Summary.of(const [100, 101, 99, 100, 5000]);

      expect(summary.median, 100);
      expect(summary.mad, 1);
      expect(summary.max, 5000);
    });

    test('summarizes one sample', () {
      final summary = Summary.of(const [7]);

      expect(summary.median, 7);
      expect(summary.p90, 7);
      expect(summary.mad, 0);
    });

    test('reports a madPercent of 0 when the median is 0', () {
      expect(Summary.of(const [0, 0, 1]).madPercent, 0);
    });

    test('rejects an empty list', () {
      expect(() => Summary.of(const []), throwsArgumentError);
    });
  });

  group('percentile', () {
    final List<double> sorted = [for (var i = 1; i <= 10; i++) i.toDouble()];

    test('returns the nearest-rank sample', () {
      expect(percentile(sorted, 90), 9);
      expect(percentile(sorted, 91), 10);
      expect(percentile(sorted, 50), 5);
      expect(percentile(sorted, 100), 10);
      expect(percentile(sorted, 1), 1);
    });

    test('rejects percentages outside (0, 100]', () {
      expect(() => percentile(sorted, 0), throwsRangeError);
      expect(() => percentile(sorted, 101), throwsRangeError);
    });

    test('rejects an empty list', () {
      expect(() => percentile([], 50), throwsArgumentError);
    });
  });
}
