// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Covers the link parsing and destination rewriting shared by
// check-absolute-paths, check-relative-paths, and pub-archive-includes-skill.

import 'package:skills_lint/src/markdown_links.dart';
import 'package:skills_lint/src/models/source_region.dart';
import 'package:skills_lint/src/skill_links.dart';
import 'package:test/test.dart';

void main() {
  group('markdownLinksIn', () {
    List<String> targetsIn(String markdown) => [
      for (final MarkdownLink link in markdownLinksIn(markdown)) link.target,
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

    test('rejects text that is not a valid inline or reference link', () {
      expect(
        targetsIn(
          '[a] (a.md) [b](b c.md) [c](<c\n.md>) [d](d(.md "t") [e]\n\n(e.md) '
          '[f](<f.md>"no-space") [g][undefined]\n',
        ),
        isEmpty,
      );
    });

    test('deactivates outer link brackets when an inner link closes', () {
      expect(
        targetsIn('Text [outer [inner](inner.md)](outer.md) and ![img [inner](a.md)](pic.png)\n'),
        ['inner.md', 'a.md', 'pic.png'],
      );
    });

    test('resolves full, collapsed and shortcut reference links and images', () {
      const markdown =
          'See [the guide][Guide], [API\n  Ref][], [shortcut], and ![logo][img].\n'
          '\n'
          '[guide]: <my guide.md> "Guide"\n'
          '[api ref]:\n'
          '  docs/api(v2).md\n'
          '  "API"\n'
          '[SHORTCUT]: quick.md\n'
          '[img]: assets/logo.png\n'
          '[unused]: not_referenced.md\n';
      expect(targetsIn(markdown), [
        'my guide.md',
        'docs/api(v2).md',
        'quick.md',
        'assets/logo.png',
      ]);
    });

    test('uses the first definition when a reference label is defined twice', () {
      const markdown =
          '[ref]: first.md\n'
          '[REF]: second.md\n'
          '\n'
          'See [ref].\n';
      expect(targetsIn(markdown), ['first.md']);
    });

    test('does not treat a line with trailing non-title text as a reference definition', () {
      const markdown = '[Note]: see [guide](guide.md)\n';
      expect(targetsIn(markdown), ['guide.md']);
    });

    test('does not treat [foo] in [foo][undefined] as a shortcut link, and scans after it', () {
      const markdown =
          '[foo]: foo.md\n'
          '\n'
          '[foo][undefined](inline.md)\n';
      expect(targetsIn(markdown), ['inline.md']);
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

    test('ends a code span at the end of a heading, list item or quoted paragraph', () {
      expect(
        targetsIn(
          '# The ` key\n[a](a.md) then `x`\n'
          '- the ` key\n- [b](b.md) then `x`\n'
          '> a `\n>\n> [c](c.md) `\n',
        ),
        ['a.md', 'b.md', 'c.md'],
      );
    });

    test('ends a paragraph at a blank line with a carriage return', () {
      expect(targetsIn('[a\r\n\r\nb](b.md) `x\r\n \r\n[c](c.md)`\r\n'), ['c.md']);
    });

    test('keeps a code span that never closes as text', () {
      expect(targetsIn('A ``tick` then [a](a.md)\n'), ['a.md']);
    });

    test('computes 1-based line and column regions shifted by startLine', () {
      const markdown = 'See [a](<my a.md>) and\n![logo][img].\n\n[img]: logo.png\n';
      final List<MarkdownLink> links = markdownLinksIn(markdown, startLine: 5);
      expect(
        [
          for (final MarkdownLink l in links)
            (
              l.target,
              l.region.startLine,
              l.region.startColumn,
              l.region.endLine,
              l.region.endColumn,
            ),
        ],
        [('my a.md', 5, 5, 5, 19), ('logo.png', 6, 1, 6, 13)],
      );
      expect(links.first.region, isA<SourceRegion>());
    });

    test('reads a fenced block to the end when it never closes', () {
      expect(targetsIn('[a](a.md)\n```\n[b](b.md)\n'), ['a.md']);
    });

    test('ends a fenced block only at a closing fence as long as the opening one', () {
      expect(targetsIn('````\n```\n[a](a.md)\n````\n[b](b.md)\n'), ['b.md']);
    });

    test('skips a fenced block inside a blockquote and resumes when the quote ends', () {
      expect(targetsIn('> ```\n> [a](a.md)\n\n[b](b.md)\n'), ['b.md']);
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

  group('replaceMarkdownLinkTargets', () {
    test('rewrites inline and shared reference definitions in source order, wrapping spaces', () {
      const input =
          '[top]: /abs/top_link.md "Top"\n'
          '\n'
          'See [first][top], [inline](/abs/plain.md "Title"), and [second][top].\n'
          'Also see [bottom] and [keep](/abs/keep.md).\n'
          '\n'
          '[bottom]: /abs/a(b).md\n'
          '[unused]: /abs/unused.md\n';
      final String rewritten = replaceMarkdownLinkTargets(input, (String target) {
        return switch (target) {
          '/abs/top_link.md' => '../my file.md',
          '/abs/plain.md' => '../plain.md',
          '/abs/a(b).md' => '../a(b).md',
          _ => null,
        };
      });
      expect(
        rewritten,
        '[top]: <../my file.md> "Top"\n'
        '\n'
        'See [first][top], [inline](../plain.md "Title"), and [second][top].\n'
        'Also see [bottom] and [keep](/abs/keep.md).\n'
        '\n'
        '[bottom]: <../a(b).md>\n'
        '[unused]: /abs/unused.md\n',
      );
      expect(
        [for (final MarkdownLink link in markdownLinksIn(rewritten)) link.target],
        ['../my file.md', '../plain.md', '../my file.md', '../a(b).md', '/abs/keep.md'],
      );
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
