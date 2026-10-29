// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Picks the candidate names closest to a name that matches none of them.
library;

import 'levenshtein.dart';

/// Finds the names in [candidates] closest to [name], sorted, or an empty
/// list when nothing is close enough.
///
/// Names are compared without regard to case, and a candidate qualifies when
/// its edit distance is at most [maxDistance]. Callers choose [maxDistance]
/// because a good limit depends on what is being compared. Duplicates are
/// removed.
///
/// When several candidates are equally close, all of them are returned, so
/// the caller can offer every likely fix. The result is sorted, so it does
/// not depend on the order of [candidates].
List<String> closestNames(String name, Iterable<String> candidates, {required int maxDistance}) {
  final String target = name.toLowerCase();
  if (target.isEmpty || maxDistance < 0) {
    return const [];
  }
  var best = <String>{};
  int bestDistance = maxDistance + 1;
  for (final candidate in candidates) {
    final int distance = levenshtein(target, candidate.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = {candidate};
    } else if (distance == bestDistance && distance <= maxDistance) {
      best.add(candidate);
    }
  }
  return best.toList()..sort();
}

/// A third of the length of [name], and at least 1 for a name that is not
/// empty; 0 for an empty name.
///
/// This is one possible `maxDistance` for [closestNames], not a default.
/// Each caller picks the limit that fits what it compares.
int oneThirdDistanceLimit(String name) =>
    name.isEmpty ? 0 : (name.length ~/ 3).clamp(1, name.length);
