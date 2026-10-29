// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/suggestions/closest_name.dart';
import 'package:test/test.dart';

void main() {
  group('closestNames', () {
    test('picks the closest candidate within maxDistance', () {
      expect(
        closestNames('check-relative-path', [
          'check-relative-paths',
          'check-absolute-paths',
        ], maxDistance: 6),
        ['check-relative-paths'],
      );
    });

    test('compares without regard to case and keeps the candidate as written', () {
      expect(closestNames('readme.md', ['README.MD', 'other.txt'], maxDistance: 3), ['README.MD']);
    });

    test('returns nothing when no candidate is within maxDistance', () {
      // 'abcdef' and 'abcxyz' have edit distance 3.
      expect(closestNames('abcdef', ['abcxyz'], maxDistance: 2), isEmpty);
      expect(closestNames('abcdef', ['abcxyz'], maxDistance: 3), ['abcxyz']);
      expect(closestNames('abcdef', ['abcxyz'], maxDistance: 0), isEmpty);
    });

    test('returns every equally close candidate, sorted', () {
      expect(closestNames('team-rule-c', ['team-rule-b', 'team-rule-a'], maxDistance: 3), [
        'team-rule-a',
        'team-rule-b',
      ]);
    });

    test('returns the same result for any candidate order', () {
      const candidates = ['abcdefxx', 'abcdefyy', 'abcdefgx'];
      for (final List<String> order in [candidates, candidates.reversed.toList()]) {
        expect(closestNames('abcdefgh', order, maxDistance: 2), ['abcdefgx']);
      }
    });

    test('removes repeated candidates', () {
      expect(closestNames('team-rule-c', ['team-rule-a', 'team-rule-a'], maxDistance: 3), [
        'team-rule-a',
      ]);
    });

    test('with maxDistance 0, finds a name that differs only in case', () {
      expect(closestNames('readme.md', ['README.md', 'readme.mdx'], maxDistance: 0), ['README.md']);
    });

    test('returns nothing for an empty name', () {
      expect(closestNames('', ['a'], maxDistance: 1), isEmpty);
    });
  });

  group('oneThirdDistanceLimit', () {
    test('is a third of the length, at least 1 for a non-empty name, and 0 for an empty one', () {
      expect(oneThirdDistanceLimit('abcdef'), 2);
      expect(oneThirdDistanceLimit('ab'), 1);
      expect(oneThirdDistanceLimit(''), 0);
    });
  });
}
