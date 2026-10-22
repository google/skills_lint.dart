// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Covers the link parsing that check-relative-paths and
// pub-archive-includes-skill share.

import 'package:skills_lint/src/skill_links.dart';
import 'package:test/test.dart';

void main() {
  test('linkTargetOf drops a title and surrounding spaces', () {
    expect(linkTargetOf(' references/a.md "A guide" '), 'references/a.md');
  });

  test('isUrlOrAnchor accepts schemes and anchors, not relative paths', () {
    expect(
      {
        for (final link in ['https://dart.dev', 'mailto:a@b.c', '#steps', 'a.md'])
          link: isUrlOrAnchor(link),
      },
      {'https://dart.dev': true, 'mailto:a@b.c': true, '#steps': true, 'a.md': false},
    );
  });

  test('isAbsoluteLink accepts POSIX and Windows absolute paths', () {
    expect(
      [isAbsoluteLink('/a.md'), isAbsoluteLink(r'C:\a.md'), isAbsoluteLink('a.md')],
      [true, true, false],
    );
  });

  test('linkFilePath decodes escapes but keeps unsafe results as written', () {
    expect(
      {
        for (final link in ['my%20file.md', 'x%E9.md', '%2Fetc%2Fpasswd', 'a.md%00b'])
          link: linkFilePath(link),
      },
      {
        'my%20file.md': 'my file.md',
        'x%E9.md': 'x%E9.md',
        '%2Fetc%2Fpasswd': '%2Fetc%2Fpasswd',
        'a.md%00b': 'a.md%00b',
      },
    );
  });
}
