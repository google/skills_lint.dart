// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Picks the existing sibling closest to a name that does not exist.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'levenshtein.dart';

/// The kind of file system entry [closestSiblingName] may suggest.
enum SiblingKind {
  /// Only files are candidates.
  file,

  /// Only directories are candidates.
  directory,
}

/// Returns the name of the entry in [parent] closest to [missingName], or
/// `null` when nothing is close enough.
///
/// Only entries of [kind] are candidates. Names are compared without regard
/// to case, and a candidate qualifies when its edit distance is at most a
/// third of the length of [missingName] (and at least 1).
///
/// Returns `null` when [parent] does not exist or cannot be listed, when no
/// candidate qualifies, or when two candidates are equally close. Listing
/// order depends on the file system, so picking either one of a tie would
/// make the suggestion differ between platforms.
String? closestSiblingName(Directory parent, String missingName, {required SiblingKind kind}) {
  final String missing = missingName.toLowerCase();
  if (missing.isEmpty) {
    return null;
  }

  final int threshold = (missing.length ~/ 3).clamp(1, missing.length);

  final List<FileSystemEntity> entries;
  try {
    entries = parent.listSync();
  } on FileSystemException {
    return null;
  }

  String? best;
  int bestDistance = threshold + 1;
  var tied = false;
  for (final entity in entries) {
    if ((entity is Directory) != (kind == SiblingKind.directory)) {
      continue;
    }
    final String candidate = p.basename(entity.path);
    if (candidate == missingName) {
      continue;
    }
    final int distance = levenshtein(missing, candidate.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
      tied = false;
    } else if (distance == bestDistance && best != null) {
      tied = true;
    }
  }

  return tied ? null : best;
}
