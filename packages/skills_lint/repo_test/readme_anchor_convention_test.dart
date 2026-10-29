// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/readme_anchors.dart';
import 'src/repo_paths.dart';

/// The prefix of every link into this package's README on pub.dev.
const String _readmeUrl = 'https://pub.dev/packages/skills_lint';

/// A link from a page outside this repository into this package's docs.
///
/// `target` is the full URL the outside page links to. `linkedFrom` is the
/// URL of the page that contains the link: the page to update if the target
/// is removed on purpose.
typedef ExternalLink = ({String target, String linkedFrom});

/// Links into this package's docs that pages outside this repository rely on.
///
/// Add an entry when another page starts linking to a README section. To
/// remove a section on purpose, update the `linkedFrom` page first, then
/// delete the entry.
const List<ExternalLink> externalLinks = [
  (target: '$_readmeUrl#rule-precedence', linkedFrom: 'https://dart.dev/ai/package-skills'),
  (target: '$_readmeUrl#built-in-rules', linkedFrom: 'https://dart.dev/ai/package-skills'),
  (target: '$_readmeUrl#3-custom-rules', linkedFrom: 'https://dart.dev/ai/package-skills'),
  (target: '$_readmeUrl#recipes', linkedFrom: 'https://dart.dev/ai/package-skills'),
];

/// Fails when a link in [externalLinks] would stop reaching its section.
///
/// pub.dev renders README.md and derives each heading's anchor from its text.
/// If a heading is renamed or removed, the outside link still loads the page
/// but no longer jumps to the section, and nothing else in this repo notices.
/// This test reads the local README only and makes no network requests.
void main() {
  test('every externally linked README anchor still has a heading', () {
    final String readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
    final Set<String> anchors = headingAnchors(readme).toSet();
    final List<String> broken = [
      for (final ExternalLink link in externalLinks)
        if (!anchors.contains(_readmeAnchor(link.target)))
          '${link.target}\n  linked from ${link.linkedFrom}',
    ];
    expect(
      broken,
      isEmpty,
      reason:
          'README.md no longer has a heading for these links:\n'
          '${broken.join('\n')}\n\n'
          'Restore the heading text. If the section was removed on purpose, '
          'update the linking page, then delete the entry from externalLinks.',
    );
  });
}

/// The README anchor in [target], which must be a `$_readmeUrl#<anchor>` URL.
String _readmeAnchor(String target) {
  const prefix = '$_readmeUrl#';
  if (!target.startsWith(prefix) || target.length == prefix.length) {
    fail('$target is not a $prefix<anchor> link; this test checks README anchors only.');
  }
  return target.substring(prefix.length);
}
