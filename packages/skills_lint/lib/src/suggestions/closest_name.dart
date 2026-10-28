// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Picks the candidate names closest to a name that matches none of them.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'levenshtein.dart';

/// Finds the names in [candidates] closest to [name], sorted, or an empty
/// list when nothing is close enough.
///
/// Names are compared without regard to case, and a candidate qualifies when
/// its edit distance is at most [maxDistance]. Callers choose [maxDistance]
/// because a good limit depends on what is being compared. A candidate equal
/// to [name] is skipped, and duplicates are removed.
///
/// When several candidates are equally close, all of them are returned, so
/// the caller can offer every likely fix. The result is sorted, so it does
/// not depend on the order of [candidates].
List<String> closestNames(String name, Iterable<String> candidates, {required int maxDistance}) {
  final String target = name.toLowerCase();
  if (target.isEmpty || maxDistance <= 0) {
    return const [];
  }
  var best = <String>{};
  int bestDistance = maxDistance + 1;
  for (final candidate in candidates) {
    if (candidate == name) {
      continue;
    }
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

/// The edit distance limit that path and rule name suggestions use: a third
/// of the length of [name], and at least 1.
int thirdOfLength(String name) => name.isEmpty ? 0 : (name.length ~/ 3).clamp(1, name.length);

/// The kind of file system entry [closestSiblingNames] may suggest.
enum SiblingKind {
  /// Only files are candidates.
  file,

  /// Only directories are candidates.
  directory,
}

/// Finds the names of the entries in [parent] closest to [missingName].
///
/// Only entries of [kind] are candidates. Calls [closestNames] on their
/// basenames with a limit of [thirdOfLength] of [missingName].
///
/// Returns an empty list when [parent] does not exist or cannot be listed,
/// or when no candidate qualifies.
List<String> closestSiblingNames(
  Directory parent,
  String missingName, {
  required SiblingKind kind,
}) {
  final List<FileSystemEntity> entries;
  try {
    entries = parent.listSync();
  } on FileSystemException {
    return const [];
  }
  return closestNames(missingName, [
    for (final entity in entries)
      if ((entity is Directory) == (kind == SiblingKind.directory)) p.basename(entity.path),
  ], maxDistance: thirdOfLength(missingName));
}

/// Formats [names] as a "Did you mean" question, such as
/// `Did you mean "a"?` or `Did you mean "a" or "b"?`, quoting each name with
/// [quote].
String didYouMean(List<String> names, {String quote = '"'}) {
  final List<String> quoted = [for (final n in names) '$quote$n$quote'];
  final String joined = quoted.length <= 2
      ? quoted.join(' or ')
      : '${quoted.sublist(0, quoted.length - 1).join(', ')}, or ${quoted.last}';
  return 'Did you mean $joined?';
}
