// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Turns Markdown headings into the anchors that pub.dev and GitHub link to.
library;

final RegExp _heading = RegExp(r'^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _fence = RegExp(r'^ {0,3}(```|~~~)');
final RegExp _notSlugChar = RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true);

/// Returns the anchor for one heading's [text], before duplicates are
/// numbered.
///
/// Follows the GitHub slug rules that pub.dev also uses: lowercase, drop
/// every character that is not a letter, digit, space, `_` or `-`, then
/// turn each space into `-`. So `3. Custom Rules` becomes `3-custom-rules`
/// and `` `install.sh` — Linux `` becomes `installsh--linux`.
String slugify(String text) => text.toLowerCase().replaceAll(_notSlugChar, '').replaceAll(' ', '-');

/// Returns every heading anchor in [markdown], in document order.
///
/// Lines inside fenced code blocks are skipped, since a `#` comment there is
/// not a heading. A repeated anchor gets `-1`, `-2` and so on, as GitHub
/// does.
List<String> headingAnchors(String markdown) {
  final List<String> anchors = [];
  final Map<String, int> seen = {};
  String? openFence;
  for (final String line in markdown.split('\n')) {
    final Match? fence = _fence.firstMatch(line);
    if (fence != null) {
      if (openFence == null) {
        openFence = fence[1];
      } else if (fence[1] == openFence) {
        openFence = null;
      }
      continue;
    }
    if (openFence != null) {
      continue;
    }
    final Match? heading = _heading.firstMatch(line.trimRight());
    if (heading == null) {
      continue;
    }
    final String slug = slugify(heading[2]!);
    final int count = seen[slug] ?? 0;
    seen[slug] = count + 1;
    anchors.add(count == 0 ? slug : '$slug-$count');
  }
  return anchors;
}
