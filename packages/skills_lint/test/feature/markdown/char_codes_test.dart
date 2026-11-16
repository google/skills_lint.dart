// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/feature/markdown/char_codes.dart';
import 'package:test/test.dart';

void main() {
  test('isAsciiPunctuation accepts exactly the ASCII punctuation characters', () {
    const punctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';
    expect([
      for (var char = 0; char < 0x80; char++)
        if (isAsciiPunctuation(char)) char,
    ], punctuation.codeUnits);
  });

  test('isAsciiWhitespace accepts spaces, tabs and line endings only', () {
    expect(
      [for (final char in ' \t\n\rx'.codeUnits) isAsciiWhitespace(char)],
      [true, true, true, true, false],
    );
  });
}
