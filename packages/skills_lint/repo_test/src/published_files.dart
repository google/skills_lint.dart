// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Reads the file list that `dart pub publish --dry-run` prints.
library;

/// Returns the package-relative paths of the files in the tree that
/// `dart pub publish --dry-run` prints in [output].
///
/// Each tree line is a run of four-character indents, a `├── ` or `└── `
/// connector, and a name, followed by ` (<size>)` for files.
Set<String> parsePublishedFiles(String output) {
  final entry = RegExp(r'^((?:│   |    )*)[├└]── (.+?)( \([^)]*\))?\r?$');
  final List<String> directories = [];
  final Set<String> files = {};
  for (final String line in output.split('\n')) {
    final RegExpMatch? match = entry.firstMatch(line);
    if (match == null) {
      continue;
    }
    final int depth = match.group(1)!.length ~/ 4;
    directories.length = depth;
    final String name = match.group(2)!;
    if (match.group(3) == null) {
      directories.add(name);
    } else {
      files.add([...directories, name].join('/'));
    }
  }
  return files;
}
