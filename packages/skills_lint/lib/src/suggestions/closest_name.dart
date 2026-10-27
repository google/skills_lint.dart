// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Picks the candidate name closest to a name that matches none of them.
library;

import 'levenshtein.dart';

/// Finds the name in [candidates] closest to [name], or `null` when nothing
/// is close enough.
///
/// Names are compared without regard to case, and a candidate qualifies when
/// its edit distance is at most a third of the length of [name] (and at
/// least 1). A candidate equal to [name] is skipped.
///
/// Returns `null` when no candidate qualifies, or when two different
/// candidates are equally close, because picking either one would depend on
/// the order of [candidates].
String? closestName(String name, Iterable<String> candidates) {
  final String target = name.toLowerCase();
  if (target.isEmpty) {
    return null;
  }
  final int threshold = (target.length ~/ 3).clamp(1, target.length);

  String? best;
  int bestDistance = threshold + 1;
  var tied = false;
  for (final candidate in candidates) {
    if (candidate == name) {
      continue;
    }
    final int distance = levenshtein(target, candidate.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
      tied = false;
    } else if (distance == bestDistance && best != null && candidate != best) {
      tied = true;
    }
  }
  return tied ? null : best;
}
