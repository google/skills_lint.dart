// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import 'markdown_links.dart';
import 'models/skill_context.dart';

/// Links and images in the Markdown body of [context], after any YAML
/// frontmatter, with 1-based regions in [SkillContext.rawContent].
List<MarkdownLink> bodyLinksOf(SkillContext context) {
  final String rawContent = context.rawContent;
  final int bodyStart = SkillContext.skillStartRegex.firstMatch(rawContent)?.end ?? 0;
  if (bodyStart >= rawContent.length) {
    return const [];
  }
  return markdownLinksIn(
    rawContent.substring(bodyStart),
    startLine: context.offsetToLine(bodyStart),
  );
}

/// Rewrites referenced link destinations in the Markdown body of [context]
/// wherever [rewrite] returns a non-null replacement, preserving any YAML
/// frontmatter untouched.
String replaceBodyLinkTargets(SkillContext context, String? Function(String target) rewrite) {
  final String rawContent = context.rawContent;
  final int bodyStart = SkillContext.skillStartRegex.firstMatch(rawContent)?.end ?? 0;
  if (bodyStart >= rawContent.length) {
    return rawContent;
  }
  final String frontmatter = rawContent.substring(0, bodyStart);
  final String rewrittenBody = replaceMarkdownLinkTargets(rawContent.substring(bodyStart), rewrite);
  return '$frontmatter$rewrittenBody';
}

/// Whether the link target [path] is an empty self-link, a URL with a scheme
/// (such as `https:` or `mailto:`), or an anchor in the current file.
bool isUrlOrAnchor(String path) {
  if (path.isEmpty) {
    return true;
  }
  final Uri? uri = Uri.tryParse(path);
  return uri != null && (uri.hasScheme || path.startsWith('#'));
}

/// Whether the link target [path] is an absolute path on any platform.
bool isAbsoluteLink(String path) => p.isAbsolute(path) || p.windows.isAbsolute(path);

/// File path that the link target [path] points to, with percent escapes
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
