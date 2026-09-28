// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Suggests the directory a user meant when a target directory is missing.
///
/// `lib/src/suggestions/` holds the code that works out "Did you mean"
/// suggestions for rules and diagnostics. Nothing in it is exported.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

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
/// An absolute [declaredText], or one starting with `~`, yields an absolute
/// suggestion. Otherwise the suggestion is relative to [baseDirectory] and
/// uses forward slashes.
String? suggestDirectory({
  required String declaredText,
  required String resolvedPath,
  required String baseDirectory,
  String? workingDirectory,
}) {
  final String? candidate =
      _resolvedFromWorkingDirectory(declaredText, resolvedPath, workingDirectory) ??
      _withOneFolderCorrected(resolvedPath);
  if (candidate == null) {
    return null;
  }
  if (p.isAbsolute(declaredText) || declaredText.startsWith('~')) {
    return candidate;
  }
  return p.relative(candidate, from: baseDirectory).replaceAll(r'\', '/');
}

/// Resolves a relative [declaredText] against [workingDirectory], returning
/// the result when it is an existing directory other than [resolvedPath].
///
/// This builds a hypothetical path to test for existence; it does not anchor
/// a path the tool goes on to use, so it stays out of `canonicalizePath`.
String? _resolvedFromWorkingDirectory(
  String declaredText,
  String resolvedPath,
  String? workingDirectory,
) {
  if (workingDirectory == null || !p.isRelative(declaredText) || declaredText.startsWith('~')) {
    return null;
  }
  final String candidate = p.normalize(p.join(workingDirectory, declaredText));
  if (p.equals(candidate, resolvedPath) || !Directory(candidate).existsSync()) {
    return null;
  }
  return candidate;
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
