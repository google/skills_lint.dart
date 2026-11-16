// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Covers the skill-level link helpers shared by check-absolute-paths,
// check-relative-paths, and pub-archive-includes-skill.

import 'dart:io';

import 'package:skills_lint/src/feature/markdown/markdown_links.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/skill_links.dart';
import 'package:test/test.dart';

void main() {
  _defineRewriteAndHelperTests();
}

void _defineRewriteAndHelperTests() {
  group('bodyLinksOf', () {
    test('ignores link syntax inside YAML frontmatter and handles an empty body', () {
      const frontmatterOnly =
          '---\n'
          'name: test-skill\n'
          'description: See [ignored](/abs/in_frontmatter.md)\n'
          '---\n';
      final emptyBodyContext = SkillContext(
        directory: Directory('test-skill'),
        rawContent: frontmatterOnly,
      );
      expect(bodyLinksOf(emptyBodyContext), isEmpty);

      const withBody = '$frontmatterOnly[real](/abs/in_body.md)\n';
      final context = SkillContext(directory: Directory('test-skill'), rawContent: withBody);
      final List<MarkdownLink> links = bodyLinksOf(context);
      expect(
        [for (final MarkdownLink l in links) (l.target, l.region.startLine)],
        [('/abs/in_body.md', 5)],
      );
      expect(
        replaceLinkDestinations(withBody, {links.single.destination: 'relative.md'}),
        '$frontmatterOnly[real](relative.md)\n',
      );
    });
  });

  test('isUrlOrAnchor accepts empty self-links, schemes and anchors, not relative paths', () {
    expect(
      {
        for (final link in ['', 'https://dart.dev', 'mailto:a@b.c', '#steps', 'a.md'])
          link: isUrlOrAnchor(link),
      },
      {'': true, 'https://dart.dev': true, 'mailto:a@b.c': true, '#steps': true, 'a.md': false},
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
