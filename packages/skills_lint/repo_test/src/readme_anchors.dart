// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Turns Markdown headings into the anchors that pub.dev links to.
///
/// pub.dev renders READMEs with package:markdown, so these rules copy its
/// `BlockSyntax.generateAnchorHash` and `HtmlRenderer.uniquifyId`:
/// https://github.com/dart-lang/tools/blob/main/pkgs/markdown/lib/src/block_syntaxes/block_syntax.dart
/// https://github.com/dart-lang/tools/blob/main/pkgs/markdown/lib/src/html_renderer.dart
library;

final RegExp _heading = RegExp(r'^ {0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$');
final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final RegExp _notSlugChar = RegExp('[^a-z0-9 _-]');
final RegExp _whitespace = RegExp(r'\s');

/// The anchor for one heading's [text], before repeats are numbered.
///
/// Lowercases, trims, drops every character other than ASCII letters,
/// digits, space, `_` and `-`, then turns each remaining space into
/// `-`. So `3. Custom Rules` becomes `3-custom-rules` and
/// `` `install.sh` — Linux `` becomes `installsh--linux`.
///
/// [text] is the heading source. package:markdown slugs the rendered text,
/// so a heading with a link or emphasis can differ; this README's linked
/// headings have neither.
String slugify(String text) =>
    text.toLowerCase().trim().replaceAll(_notSlugChar, '').replaceAll(_whitespace, '-');

/// Every heading anchor in [markdown], in document order.
///
/// Lines inside fenced code blocks are skipped, since a `#` comment there is
/// not a heading. Setext headings (underlined with `===` or `---`) are not
/// recognized; the README uses ATX `#` headings only. A repeated anchor gets `-2`, `-3` and so on, as pub.dev
/// does.
List<String> headingAnchors(String markdown) {
  final List<String> anchors = [];
  final Set<String> used = {};
  String? openFence;
  for (final String line in markdown.split('\n')) {
    final String? fence = _fence.firstMatch(line)?[1];
    if (openFence == null && fence != null) {
      openFence = fence;
      continue;
    }
    if (openFence != null) {
      if (fence != null && fence[0] == openFence[0] && fence.length >= openFence.length) {
        openFence = null;
      }
      continue;
    }
    final Match? heading = _heading.firstMatch(line.trimRight());
    if (heading != null) {
      anchors.add(_uniquify(slugify(heading[2]!), used));
    }
  }
  return anchors;
}

String _uniquify(String slug, Set<String> used) {
  var anchor = slug;
  for (var suffix = 2; used.contains(anchor); suffix++) {
    anchor = '$slug-$suffix';
  }
  used.add(anchor);
  return anchor;
}
