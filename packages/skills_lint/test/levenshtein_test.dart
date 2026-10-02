// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/suggestions/levenshtein.dart';
import 'package:test/test.dart';

void main() {
  group('levenshtein', () {
    test('handles empty strings', () {
      expect(levenshtein('', ''), 0);
      expect(levenshtein('', 'dart'), 4);
      expect(levenshtein('dart', ''), 4);
      expect(levenshtein('', '\u{1F600}'), 1);
    });

    test('returns zero for identical strings', () {
      expect(levenshtein('skills', 'skills'), 0);
    });

    test('counts one insertion', () {
      expect(levenshtein('skill', 'skills'), 1);
    });

    test('counts one deletion', () {
      expect(levenshtein('skills', 'skill'), 1);
    });

    test('counts one substitution', () {
      expect(levenshtein('skill', 'spill'), 1);
    });

    test('is case-sensitive', () {
      expect(levenshtein('Skill', 'skill'), 1);
    });

    test('counts Unicode code points instead of UTF-16 code units', () {
      expect(levenshtein('a\u{1F600}b', 'ab'), 1);
    });

    test('handles multiple edits', () {
      expect(levenshtein('kitten', 'sitting'), 3);
    });

    test('counts a transposition as two edits', () {
      expect(levenshtein('ab', 'ba'), 2);
    });
  });
}
