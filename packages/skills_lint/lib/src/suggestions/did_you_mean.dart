// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Formats [names] as a question, such as `Did you mean "a"?` or
/// `Did you mean "a" or "b"?`, wrapping each name in [quote].
///
/// [names] must not be empty.
String didYouMean(List<String> names, {String quote = '"'}) {
  final List<String> quoted = [for (final name in names) '$quote$name$quote'];
  final String choices = switch (quoted) {
    [] => throw ArgumentError.value(names, 'names', 'must not be empty'),
    [final only] => only,
    [final first, final second] => '$first or $second',
    [...final others, final last] => '${others.join(', ')}, or $last',
  };
  return 'Did you mean $choices?';
}
