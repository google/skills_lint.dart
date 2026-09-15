// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/models/source_region.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('SourceRegion', () {
    test('instantiates with startLine and optional coordinates', () {
      const region = SourceRegion(startLine: 2, startColumn: 5, endLine: 4, endColumn: 10);

      expect(region.startLine, equals(2));
      expect(region.startColumn, equals(5));
      expect(region.endLine, equals(4));
      expect(region.endColumn, equals(10));
    });

    test('wholeFile points to line 1 with no other coordinates', () {
      expect(SourceRegion.wholeFile.startLine, equals(1));
      expect(SourceRegion.wholeFile.startColumn, isNull);
      expect(SourceRegion.wholeFile.endLine, isNull);
      expect(SourceRegion.wholeFile.endColumn, isNull);
    });

    test('asserts that startLine is >= 1', () {
      expect(() => SourceRegion(startLine: 0), throwsA(isA<AssertionError>()));
      expect(() => SourceRegion(startLine: -1), throwsA(isA<AssertionError>()));
    });

    test('implements value equality and hashCode', () {
      const region1 = SourceRegion(startLine: 2, startColumn: 3, endLine: 4, endColumn: 5);
      const region2 = SourceRegion(startLine: 2, startColumn: 3, endLine: 4, endColumn: 5);
      const region3 = SourceRegion(startLine: 2, startColumn: 3, endLine: 4, endColumn: 6);

      expect(region1, equals(region2));
      expect(region1.hashCode, equals(region2.hashCode));
      expect(region1, isNot(equals(region3)));
    });

    test('serializes to and from JSON using expectJsonRoundTrip', () {
      const full = SourceRegion(startLine: 10, startColumn: 2, endLine: 12, endColumn: 8);
      expectJsonRoundTrip<SourceRegion>(
        instance: full,
        toJson: (r) => r.toJson(),
        fromJson: SourceRegion.fromJson,
        expectValueEquality: true,
      );

      const SourceRegion minimal = SourceRegion.wholeFile;
      expectJsonRoundTrip<SourceRegion>(
        instance: minimal,
        toJson: (r) => r.toJson(),
        fromJson: SourceRegion.fromJson,
        expectValueEquality: true,
      );
    });

    test('negative handling on invalid coordinates', () {
      expect(
        () => SourceRegion.fromJson(const {'startLine': 'not_an_int'}),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
