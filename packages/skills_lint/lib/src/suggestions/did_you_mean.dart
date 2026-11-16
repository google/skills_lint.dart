// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'closest_name.dart';

/// Formats [names] as a question, such as `Did you mean "a"?` or
/// `Did you mean "a" or "b"?`, wrapping each name in [quote].
///
/// [names] must not be empty.
String didYouMean(Iterable<String> names, {String quote = '"'}) {
  final List<String> quoted = [for (final name in names) '$quote$name$quote'];
  final String choices = switch (quoted) {
    [] => throw ArgumentError.value(names, 'names', 'must not be empty'),
    [final String only] => only,
    [final String first, final String second] => '$first or $second',
    [...final List<String> others, final String last] => '${others.join(', ')}, or $last',
  };
  return 'Did you mean $choices?';
}

/// Asks whether [name] meant the closest of [candidates], as [didYouMean]
/// does.
///
/// Is `null` when no candidate is within [oneThirdDistanceLimit] of [name].
String? didYouMeanClosest(String name, Iterable<String> candidates) {
  final List<String> closest = closestNames(
    name,
    candidates,
    maxDistance: oneThirdDistanceLimit(name),
  );
  return closest.isEmpty ? null : didYouMean(closest);
}
