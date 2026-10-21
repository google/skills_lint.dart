// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint_release/src/line_endings.dart';
import 'package:test/test.dart';

void main() {
  test('normalizeLineTerminators turns CRLF and lone CR into LF', () {
    expect('a\r\nb\rc\nd\r\n\r'.normalizeLineTerminators(), 'a\nb\nc\nd\n\n');
  });

  test('normalizeLineTerminators leaves LF-only text unchanged', () {
    expect('a\nb\n\n'.normalizeLineTerminators(), 'a\nb\n\n');
  });
}
