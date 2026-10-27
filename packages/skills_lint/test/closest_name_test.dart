// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/suggestions/closest_name.dart';
import 'package:test/test.dart';

void main() {
  group('closestName', () {
    test('picks the closest candidate within the threshold', () {
      expect(
        closestName('check-relative-path', ['check-relative-paths', 'check-absolute-paths']),
        'check-relative-paths',
      );
    });

    test('compares without regard to case and keeps the candidate as written', () {
      expect(closestName('readme.md', ['README.MD', 'other.txt']), 'README.MD');
    });

    test('returns null when no candidate is within a third of the length', () {
      expect(closestName('abcdef', ['uvwxyz']), isNull);
    });

    test('allows distance 1 for names shorter than three characters', () {
      expect(closestName('ab', ['ac']), 'ac');
    });

    test('returns null when two different candidates are equally close', () {
      expect(closestName('team-rule-c', ['team-rule-a', 'team-rule-b']), isNull);
    });

    test('does not count a repeated candidate as a tie', () {
      expect(closestName('team-rule-c', ['team-rule-a', 'team-rule-a']), 'team-rule-a');
    });

    test('a closer candidate after a tie wins', () {
      expect(closestName('abcdefgh', ['abcdefxx', 'abcdefyy', 'abcdefgx']), 'abcdefgx');
    });

    test('skips a candidate equal to the name', () {
      expect(closestName('same', ['same']), isNull);
    });

    test('returns null for an empty name', () {
      expect(closestName('', ['a']), isNull);
    });
  });
}
