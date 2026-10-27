// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Picks the candidate name closest to a name that matches none of them.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'levenshtein.dart';

/// Finds the name in [candidates] closest to [name], or `null` when nothing
/// is close enough.
///
/// Names are compared without regard to case, and a candidate qualifies when
/// its edit distance is at most [maxDistance]. When [maxDistance] is omitted,
/// it defaults to a third of the length of [name] (and at least 1). A
/// candidate equal to [name] is skipped.
///
/// Returns `null` when no candidate qualifies, or when two different
/// candidates are equally close, because picking either one would depend on
/// the order of [candidates].
String? closestName(String name, Iterable<String> candidates, {int? maxDistance}) {
  final String target = name.toLowerCase();
  if (target.isEmpty) {
    return null;
  }
  final int threshold = maxDistance ?? (target.length ~/ 3).clamp(1, target.length);
  if (threshold <= 0) {
    return null;
  }

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

/// The kind of file system entry [closestSiblingName] may suggest.
enum SiblingKind {
  /// Only files are candidates.
  file,

  /// Only directories are candidates.
  directory,
}

/// Finds the name of the entry in [parent] closest to [missingName], or
/// `null` when nothing is close enough.
///
/// Only entries of [kind] are candidates. Calls [closestName] on their
/// basenames, forwarding [maxDistance].
///
/// Returns `null` when [parent] does not exist or cannot be listed, when no
/// candidate qualifies, or when two candidates are equally close. Listing
/// order depends on the file system, so picking either one of a tie would
/// make the suggestion differ between platforms.
String? closestSiblingName(
  Directory parent,
  String missingName, {
  required SiblingKind kind,
  int? maxDistance,
}) {
  if (missingName.isEmpty) {
    return null;
  }
  final List<FileSystemEntity> entries;
  try {
    entries = parent.listSync();
  } on FileSystemException {
    return null;
  }
  return closestName(missingName, [
    for (final entity in entries)
      if ((entity is Directory) == (kind == SiblingKind.directory)) p.basename(entity.path),
  ], maxDistance: maxDistance);
}
