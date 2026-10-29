// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Picks the existing sibling closest to a name that does not exist.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'closest_name.dart';

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
/// Only entries of [kind] are candidates. Names are compared without regard
/// to case, and a candidate qualifies when its edit distance is at most a
/// third of the length of [missingName] (and at least 1).
///
/// Returns `null` when [parent] does not exist or cannot be listed, when no
/// candidate qualifies, or when two candidates are equally close. Listing
/// order depends on the file system, so picking either one of a tie would
/// make the suggestion differ between platforms.
String? closestSiblingName(Directory parent, String missingName, {required SiblingKind kind}) {
  final List<FileSystemEntity> entries;
  try {
    entries = parent.listSync();
  } on FileSystemException {
    return null;
  }
  final List<String> closest = closestNames(missingName, [
    for (final entity in entries)
      if ((entity is Directory) == (kind == SiblingKind.directory) &&
          p.basename(entity.path) != missingName)
        p.basename(entity.path),
  ], maxDistance: typoDistanceLimit(missingName));
  return closest.length == 1 ? closest.single : null;
}
