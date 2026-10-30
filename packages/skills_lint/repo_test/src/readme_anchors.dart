// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Finds the heading anchors pub.dev gives a package README.
library;

import 'package:markdown/markdown.dart';

/// An opening `<h1>` to `<h6>` tag that carries an `id`, capturing the id.
final RegExp _headingId = RegExp(r'<h[1-6] id="([^"]*)"');

/// Every heading anchor in [markdown], in document order.
///
/// pub.dev renders a README with package:markdown and its GitHub Web
/// extension set, which gives each heading an `id` from its text. A heading
/// whose text repeats gets `-2`, `-3` and so on. This renders [markdown] the
/// same way and reads those ids back, so a link to
/// `https://pub.dev/packages/<name>#<anchor>` works when `<anchor>` is in the
/// result.
List<String> headingAnchors(String markdown) => [
  for (final Match match in _headingId.allMatches(
    markdownToHtml(markdown, extensionSet: ExtensionSet.gitHubWeb),
  ))
    match[1]!,
];
