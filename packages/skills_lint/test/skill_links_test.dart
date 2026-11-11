// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Covers the link parsing and destination rewriting shared by
// check-absolute-paths, check-relative-paths, and pub-archive-includes-skill.

import 'dart:io';

import 'package:skills_lint/src/markdown_block_scanner.dart';
import 'package:skills_lint/src/markdown_inline_scanner.dart';
import 'package:skills_lint/src/markdown_links.dart';
import 'package:skills_lint/src/models/skill_context.dart';
import 'package:skills_lint/src/skill_links.dart';
import 'package:test/test.dart';

void main() {
  _defineMarkdownLinksTests();
  _defineScannerPipelineTests();
  _defineRewriteAndHelperTests();
}

void _defineMarkdownLinksTests() {
  group('markdownLinksIn', () {
    List<String> targetsIn(String markdown) => [
      for (final MarkdownLink link in markdownLinksIn(markdown)) link.target,
    ];

    test(
      'reads titles, spaces, escapes, Windows paths and nested images, not escaped brackets',
      () {
        expect(
          targetsIn(
            '[a]( a.md "A (guide)" ) [b](b.md \'B\') [c](c.md (C))\n'
            '[d](d\\).md) \\[e](e.md) [![f](f.png)](g.md)\n'
            '[w1](C:\\Users\\dev\\guide.md) [w2](<C:\\Program Files (x86)\\guide.md>)\n',
          ),
          [
            'a.md',
            'b.md',
            'c.md',
            r'd\).md',
            'f.png',
            'g.md',
            r'C:\Users\dev\guide.md',
            r'C:\Program Files (x86)\guide.md',
          ],
        );
      },
    );

    test('rejects text that is not a valid inline or reference link', () {
      expect(
        targetsIn(
          '[a] (a.md) [b](b c.md) [b2](b\\ c.md) [c](<c\n.md>) [d](d(.md "t") [e]\n\n(e.md) '
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
          'See [the guide][Guide], [API\n  Ref][], [shortcut], [fallback](unclosed, '
          'and ![logo][img].\n'
          '\n'
          '[guide]: <my guide.md> "Guide"\n'
          '[api ref]:\n'
          '  docs/api(v2).md\n'
          '  "API"\n'
          '[SHORTCUT]: quick.md\n'
          '[fallback]: fallback.md\n'
          '[img]: assets/logo.png\n'
          '[unused]: not_referenced.md\n';
      expect(targetsIn(markdown), [
        'my guide.md',
        'docs/api(v2).md',
        'quick.md',
        'fallback.md',
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

    test('handles fenced code, indented code and ATX headings on a list item marker line', () {
      const markdown =
          '- ```dart\n'
          '  // [in_fence](ignored.md)\n'
          '  ```\n'
          '  [after_fence](real1.md)\n'
          '-     [in_indented_code](ignored2.md)\n'
          '- # Heading with `unclosed\n'
          '  [after_heading](real2.md) `tick`\n';
      expect(targetsIn(markdown), ['real1.md', 'real2.md']);
    });

    test('tracks nested list items and blockquotes in outer-to-inner container order', () {
      const markdown =
          '10. > ```markdown\n'
          '    > [in_quoted_fence](/abs/ignored1.md)\n'
          '    > ```\n'
          '\n'
          '- Outer step\n'
          '\n'
          '  > [!NOTE]\n'
          '  > Important note.\n'
          '\n'
          '    [still_in_list](found1.md)\n';
      expect(targetsIn(markdown), ['found1.md']);
    });

    test('does not interrupt open paragraphs on empty or non-1 ordered list markers', () {
      const markdown =
          'Run `tool --step\n'
          '2. verify` and do not write `[bad](/abs/ignored.md)`.\n'
          '\n'
          'See [Section\n'
          '2. Configuration](config.md) and [item\n'
          '*\n'
          '](star.md).\n';
      expect(targetsIn(markdown), ['config.md', 'star.md']);
    });

    test('ends unclosed list fences on dedent and closes empty list items after a blank line', () {
      const markdown =
          '- ```dart\n'
          '  void main() {}\n'
          '- See [sibling](sibling.md)\n'
          '\n'
          '- ```dart\n'
          '  int x = 1;\n'
          '```\n'
          '  [in_top_level_fence](/abs/ignored1.md)\n'
          '```\n'
          '\n'
          '-\n'
          '\n'
          '    [in_indented_code](/abs/ignored2.md)\n';
      expect(targetsIn(markdown), ['sibling.md']);
    });

    test('preserves outer list indentation after a nested list ends', () {
      const markdown =
          '- Outer step\n'
          '  - Nested note\n'
          '\n'
          '  Outer continuation.\n'
          '\n'
          '    [outer_link](outer.md)\n';
      expect(targetsIn(markdown), ['outer.md']);
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
}

void _defineScannerPipelineTests() {
  group('MarkdownBlockScanner and MarkdownInlineScanner', () {
    test('separates ATX headings from paragraphs and consumes leading definitions', () {
      const markdown =
          '# Heading\n'
          '[ref]: docs/guide.md "Guide"\n'
          'See [ref].\n';
      final (List<MarkdownTextBlock> blocks, List<int> lineStarts) = MarkdownBlockScanner(
        markdown,
      ).scan();
      expect(lineStarts, [0, 10, 39]);
      expect(blocks.map((MarkdownTextBlock b) => b.allowsDefinitions), [false, true]);

      final definitions = <String, TargetSpan>{};
      final int inlineStart = consumeReferenceDefinitions(markdown, blocks[1], definitions);
      expect(definitions.keys, ['ref']);
      expect(markdown.substring(inlineStart, blocks[1].end), 'See [ref].\n');

      final matches = <LinkMatch>[];
      MarkdownInlineScanner(markdown, definitions, matches).scanRange(inlineStart, blocks[1].end);
      expect([for (final LinkMatch m in matches) m.destination.target], ['docs/guide.md']);
    });
  });
}

void _defineRewriteAndHelperTests() {
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

  group('bodyLinksOf and replaceBodyLinkTargets', () {
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
      expect(replaceBodyLinkTargets(emptyBodyContext, (_) => 'rewritten.md'), frontmatterOnly);

      const withBody = '$frontmatterOnly[real](/abs/in_body.md)\n';
      final context = SkillContext(directory: Directory('test-skill'), rawContent: withBody);
      final List<MarkdownLink> links = bodyLinksOf(context);
      expect(
        [for (final MarkdownLink l in links) (l.target, l.region.startLine)],
        [('/abs/in_body.md', 5)],
      );
      expect(
        replaceBodyLinkTargets(context, (_) => 'relative.md'),
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
