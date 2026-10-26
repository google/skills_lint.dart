// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/readme_anchors.dart';
import 'src/repo_paths.dart';

/// The dart.dev page on package skills, added in
/// https://github.com/dart-lang/site-www/pull/7572.
const String _dartDevPackageSkills = 'dart.dev /tools/pub/package-skills (dart-lang/site-www#7572)';

/// README anchors that pages outside this repository link to, as
/// `pub.dev/packages/skills_lint#<anchor>`, mapped to the page that links.
///
/// When another page starts linking to a README section, add its anchor here
/// with that page. Remove an entry only once no page links to it.
const Map<String, String> externallyLinkedAnchors = {
  'rule-precedence': _dartDevPackageSkills,
  '3-custom-rules': _dartDevPackageSkills,
  'built-in-rules': _dartDevPackageSkills,
  'recipes': _dartDevPackageSkills,
};

/// Fails when a README heading that another site links to is renamed.
///
/// pub.dev renders README.md and gives each heading an anchor. If a heading
/// is renamed or renumbered, links to the old anchor still load the page but
/// no longer jump to the section, and nothing else in this repo notices.
/// This test reads the local README only and makes no network requests.
///
/// Change this test if pub.dev stops deriving anchors from heading text.
void main() {
  test('README headings still provide every externally linked anchor', () {
    final String readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
    final Set<String> anchors = headingAnchors(readme).toSet();
    final List<String> missing = [
      for (final MapEntry<String, String> entry in externallyLinkedAnchors.entries)
        if (!anchors.contains(entry.key)) '#${entry.key}: linked from ${entry.value}',
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'packages/skills_lint/README.md has no heading for ${missing.length} '
          'externally linked anchor(s):\n${missing.join('\n')}\n\n'
          'Fix: restore the heading text, or update the linking page and then '
          'the list in repo_test/readme_anchor_convention_test.dart.',
    );
  });
}
