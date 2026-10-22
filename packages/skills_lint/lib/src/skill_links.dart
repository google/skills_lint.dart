// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

/// The link target in [linkDestination], the text between the parentheses of
/// a Markdown link, without an optional title such as `"Guide"`.
String linkTargetOf(String linkDestination) => linkDestination.trim().split(RegExp(r'\s+')).first;

/// Whether the link target [path] is a URL with a scheme, such as `https:` or
/// `mailto:`, or an anchor in this file.
bool isUrlOrAnchor(String path) {
  final Uri? uri = Uri.tryParse(path);
  return uri != null && (uri.hasScheme || path.startsWith('#'));
}

/// Whether the link target [path] is an absolute path on any platform.
bool isAbsoluteLink(String path) => p.isAbsolute(path) || p.windows.isAbsolute(path);

/// The file path that the link target [path] points to, with percent escapes
/// decoded.
///
/// A [path] that is not a valid URI, whose escapes are not valid UTF-8, such
/// as `%E9`, or that decodes to an absolute path or to one with a NUL, is
/// returned as written.
String linkFilePath(String path) {
  final Uri? uri = Uri.tryParse(path);
  if (uri == null) {
    return path;
  }
  final String decoded;
  try {
    decoded = Uri.decodeComponent(uri.path);
  } on FormatException {
    // Uri.tryParse turns a % that starts no escape into %25, so only invalid
    // UTF-8, such as %E9, makes decoding fail.
    return path;
  }
  // join would ignore the skill directory for an absolute path, and
  // File.existsSync ignores everything after a NUL.
  if (p.isAbsolute(decoded) || decoded.contains('\u0000')) {
    return path;
  }
  return decoded;
}
