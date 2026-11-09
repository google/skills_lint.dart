// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

/// A 1-based line and column in a configuration file, whose path is
/// absolute.
typedef ConfigLocation = ({String file, int line, int column});

/// Where [span] starts in [file].
ConfigLocation configLocationOf(String file, SourceSpan span) =>
    (file: file, line: span.start.line + 1, column: span.start.column + 1);

/// Formats [location] as `<file>:<line>:<column>` for diagnostics.
///
/// The file is shown as [displayConfigPath] shows it.
String formatConfigLocation(ConfigLocation location) =>
    '${displayConfigPath(location.file)}:${location.line}:${location.column}';

/// [file] relative to the working directory when it is inside that
/// directory, and [file] itself otherwise.
String displayConfigPath(String file) {
  final String workingDirectory = p.normalize(p.absolute(Directory.current.path));
  return p.isWithin(workingDirectory, file) ? p.relative(file, from: workingDirectory) : file;
}
