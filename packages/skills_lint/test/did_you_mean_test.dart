// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/suggestions/did_you_mean.dart';
import 'package:test/test.dart';

void main() {
  group('didYouMean', () {
    test('formats one, two, and three names', () {
      expect(didYouMean(['a']), 'Did you mean "a"?');
      expect(didYouMean(['a', 'b']), 'Did you mean "a" or "b"?');
      expect(didYouMean(['a', 'b', 'c'], quote: '`'), 'Did you mean `a`, `b`, or `c`?');
    });

    test('throws for an empty list', () {
      expect(() => didYouMean(const []), throwsArgumentError);
    });
  });
}
