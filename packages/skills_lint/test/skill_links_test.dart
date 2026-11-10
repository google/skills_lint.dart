// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Covers the link parsing that check-relative-paths and
// pub-archive-includes-skill share.

import 'package:skills_lint/src/markdown_links.dart';
import 'package:skills_lint/src/skill_links.dart';
import 'package:test/test.dart';

void main() {
  group('markdownLinksIn', () {
    List<String> targetsIn(String markdown) => [
      for (final link in markdownLinksIn(markdown)) link.target,
    ];

    test('reads titles, spaces, escapes and nested images, not escaped brackets', () {
      expect(
        targetsIn(
          '[a]( a.md "A (guide)" ) [b](b.md \'B\') [c](c.md (C))\n'
          '[d](d\\).md) \\[e](e.md) [![f](f.png)](g.md)\n',
        ),
        ['a.md', 'b.md', 'c.md', r'd\).md', 'f.png', 'g.md'],
      );
    });

    test('rejects text that is not an inline link', () {
      expect(
        targetsIn(
          '[a] (a.md) [b](b c.md) [c](<c\n.md>) [d](d(.md) [e]\n\n(e.md) [f][ref]\n'
          '[ref]: ref.md\n',
        ),
        isEmpty,
      );
    });

    test('ends a code span, link text and a destination at a blank line', () {
      expect(
        targetsIn(
          'Press the ` key.\n\n[a](a.md) then `x`.\n'
          '[b\n\nc](c.md)\n'
          '[d](<d\n\n.md>)\n',
        ),
        ['a.md'],
      );
    });

    test('ends a paragraph at a blank line with a carriage return', () {
      expect(targetsIn('[a\r\n\r\nb](b.md) `x\r\n \r\n[c](c.md)`\r\n'), ['c.md']);
    });

    test('keeps a code span that never closes as text', () {
      expect(targetsIn('A ``tick` then [a](a.md)\n'), ['a.md']);
    });

    test('gives offsets into the text after offset', () {
      const text = 'x [a](<my a.md>)';
      final MarkdownLink link = markdownLinksIn(text.substring(2), offset: 2).single;
      expect(
        (link.start, text.substring(link.targetStart, link.targetEnd), link.isAngleBracketed),
        (2, 'my a.md', true),
      );
    });

    test('reads a fenced block to the end when it never closes', () {
      expect(targetsIn('[a](a.md)\n```\n[b](b.md)\n'), ['a.md']);
    });

    test('ends a fenced block only at a closing fence as long as the opening one', () {
      expect(targetsIn('````\n```\n[a](a.md)\n````\n[b](b.md)\n'), ['b.md']);
    });

    test('reads a backtick line with a closing backtick as a code span, not a fence', () {
      expect(targetsIn('```a``` [a](a.md)\n'), ['a.md']);
    });

    test('ends an indented code block at a line with less indentation', () {
      expect(targetsIn('    [a](a.md)\n\n    [b](b.md)\n[c](c.md)\n'), ['c.md']);
    });

    test('reads an indented line that continues a paragraph as text', () {
      expect(targetsIn('Text\n    [a](a.md)\n'), ['a.md']);
    });

    test('reads an indented line after a list ends as code', () {
      expect(targetsIn('- item\n\nText\n\n    [a](a.md)\n'), isEmpty);
    });
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
