// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/leading_returns.dart';
import '../src/models/source.dart';

/// Pins what [findLeadingReturns] reports on small inline snippets.
void main() {
  test('reports a doc block whose first line starts with Returns', () {
    final source = Source.snippet('''
/// Returns the answer.
int answer() => 42;

class A {
  ///   Returns the name.
  String get name => 'a';
}
''');
    expect([for (final v in findLeadingReturns(source)) v.line], [1, 5]);
  });

  test('ignores Returns in a later line, paragraph, or plain comment', () {
    final source = Source.snippet('''
/// Computes the answer.
///
/// Returns 42 when nothing else is known.
int answer() => 42;

/// Lists the names, which
/// Returns-style wording may wrap onto.
List<String> names() => [];

// Returns nothing; this is not a doc comment.
void noop() {}

/// ReturnsNothing is not the word Returns.
void other() {}

//// Returns in a banner line is a plain comment.
void banner() {}
''');
    expect(findLeadingReturns(source), isEmpty);
  });

  test('treats a doc line after a gap as a new block', () {
    final source = Source.snippet('''
/// Computes the answer.
int answer() => 42;
/// Returns the question.
String question() => '?';
''');
    expect([for (final v in findLeadingReturns(source)) v.line], [3]);
  });
}
