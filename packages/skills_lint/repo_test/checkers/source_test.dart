// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/models/source.dart';

/// Pins the bases that [Source.lineOf] counts from, which every convention
/// violation's line number depends on.
void main() {
  test('lineOf takes a 0-based offset and returns a 1-based line', () {
    final source = Source.snippet('int a;\nint b;\n');
    expect(source.lineOf(0), 1);
    expect(source.lineOf(6), 1);
    expect(source.lineOf(7), 2);
  });
}
