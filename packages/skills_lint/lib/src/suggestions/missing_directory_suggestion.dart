// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Suggests the directory a user meant when a target directory is missing.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../path_utils.dart';
import 'sibling_suggestion.dart';

/// Returns the path the user most likely meant by [declaredText], written the
/// way they should type it, or `null` when no directory is a confident match.
///
/// [declaredText] is the path exactly as typed in a configuration file or on
/// the command line. [resolvedPath] is that text resolved against
/// [baseDirectory]; it is absolute, normalized, and does not exist.
/// [baseDirectory] is the directory the text was resolved against: the
/// directory holding the configuration file, or the working directory for a
/// command-line path. Pass [workingDirectory] only for configuration targets.
///
/// The first of these checks that finds an existing directory wins:
///
/// 1. When [workingDirectory] is given and [declaredText] is relative, the
///    text resolved against [workingDirectory] instead. This catches a path
///    written relative to where the tool runs rather than to the
///    configuration file.
/// 2. The path with one misspelled folder corrected: the first folder below
///    the deepest existing ancestor is swapped for its closest sibling
///    directory, and the result is kept only if the whole path exists.
///
/// A [declaredText] starting with `~/` yields a suggestion starting with `~/`
/// when the match is inside [homeDirectory], which defaults to the user's
/// home directory. An absolute [declaredText], or a `~/` one whose match is
/// outside [homeDirectory], yields an absolute suggestion. Otherwise the
/// suggestion is relative to [baseDirectory]. Relative and `~/` suggestions
/// use forward slashes.
String? suggestDirectory({
  required String declaredText,
  required String resolvedPath,
  required String baseDirectory,
  String? workingDirectory,
  String? homeDirectory,
}) {
  if (workingDirectory != null &&
      _existsFromWorkingDirectory(declaredText, resolvedPath, workingDirectory)) {
    return _relativeAcrossAnchors(declaredText, workingDirectory, baseDirectory);
  }
  final String? corrected = _withOneFolderCorrected(resolvedPath);
  if (corrected == null) {
    return null;
  }
  if (_isHomeRelative(declaredText)) {
    return _underHome(corrected, homeDirectory ?? expandPath('~'));
  }
  if (p.isAbsolute(declaredText)) {
    return corrected;
  }
  return p.relative(corrected, from: baseDirectory).replaceAll(r'\', '/');
}

/// Whether [text] starts with a home-directory prefix that `expandPath`
/// expands.
bool _isHomeRelative(String text) => text == '~' || text.startsWith('~/') || text.startsWith(r'~\');

/// [path] written as `~/...` when it is inside [home], or unchanged when it
/// is not.
String _underHome(String path, String home) {
  if (!p.isWithin(home, path)) {
    return path;
  }
  return '~/${p.relative(path, from: home).replaceAll(r'\', '/')}';
}

/// Whether a relative [declaredText] resolved against [workingDirectory] is an
/// existing directory other than [resolvedPath].
///
/// This builds a hypothetical path to test for existence; it does not anchor
/// a path the tool goes on to use, so it stays out of `canonicalizePath`.
bool _existsFromWorkingDirectory(
  String declaredText,
  String resolvedPath,
  String workingDirectory,
) {
  if (!p.isRelative(declaredText) || _isHomeRelative(declaredText)) {
    return false;
  }
  final String candidate = p.normalize(p.join(workingDirectory, declaredText));
  return !p.equals(candidate, resolvedPath) && Directory(candidate).existsSync();
}

/// Rewrites [declaredText], which exists relative to [workingDirectory], so
/// that it reads relative to [baseDirectory].
///
/// The operating system reports the working directory as a physical path,
/// while [baseDirectory] keeps whatever spelling named the configuration file.
/// Comparing the two directories by their physical paths keeps a symlinked
/// spelling from turning the suggestion into a machine-specific path, and
/// leaves any symlinks inside [declaredText] as the author wrote them.
String _relativeAcrossAnchors(String declaredText, String workingDirectory, String baseDirectory) {
  final String hop = p.relative(_physical(workingDirectory), from: _physical(baseDirectory));
  return p.normalize(p.join(hop, declaredText)).replaceAll(r'\', '/');
}

/// [directory] with symlinks resolved, or unchanged when it cannot be resolved.
String _physical(String directory) {
  try {
    return Directory(directory).resolveSymbolicLinksSync();
  } on FileSystemException {
    return directory;
  }
}

/// Corrects the first missing folder of [resolvedPath] to its closest
/// existing sibling, returning the corrected path only if it exists.
String? _withOneFolderCorrected(String resolvedPath) {
  String existing = p.dirname(resolvedPath);
  while (!Directory(existing).existsSync()) {
    final String up = p.dirname(existing);
    if (up == existing) {
      return null;
    }
    existing = up;
  }

  final List<String> missing = p.split(p.relative(resolvedPath, from: existing));
  final String? match = closestSiblingName(
    Directory(existing),
    missing.first,
    kind: SiblingKind.directory,
  );
  if (match == null) {
    return null;
  }
  final String candidate = p.joinAll(<String>[existing, match, ...missing.skip(1)]);
  return Directory(candidate).existsSync() ? candidate : null;
}
