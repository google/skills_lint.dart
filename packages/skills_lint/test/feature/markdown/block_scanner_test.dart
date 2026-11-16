// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/feature/markdown/block_scanner.dart';
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';

/// The text of each block that [markdown] splits into, with container
/// markers replaced by spaces.
List<String> blocksOf(String markdown, {int start = 0}) {
  final MarkdownBlocks scanned = scanMarkdownBlocks(SourceFile.fromString(markdown), start: start);
  return [
    for (final FileSpan block in scanned.blocks)
      scanned.text.substring(block.start.offset, block.end.offset),
  ];
}

void main() {
  test('keeps every offset and line ending of the source', () {
    const markdown = '> - item\r\n```\r\ncode\r\n```\r\ntext';
    final MarkdownBlocks scanned = scanMarkdownBlocks(SourceFile.fromString(markdown));
    expect(scanned.text, '    item\r\n   \r\n    \r\n   \r\ntext');
  });

  test('blanks the text before the start offset', () {
    expect(blocksOf('---\nname: x\n---\nBody\n', start: 16), ['Body\n']);
  });

  group('paragraphs and headings', () {
    test('ends a paragraph at a blank line', () {
      expect(blocksOf('a\nb\n\nc\n'), ['a\nb\n', 'c\n']);
    });

    test('makes each ATX heading its own block', () {
      expect(blocksOf('# One\ntext\n## Two\n'), ['# One\n', 'text\n', '## Two\n']);
    });

    test('reads 7 #s or a # without a space as text', () {
      expect(blocksOf('####### a\n#b\n'), ['####### a\n#b\n']);
    });

    test('ends a paragraph at a setext underline or a thematic break', () {
      expect(blocksOf('a\n===\nb\n---\nc\n***\nd\n'), ['a\n', 'b\n', 'c\n', 'd\n']);
    });
  });

  group('code blocks', () {
    test('skips a fenced code block of backticks or tildes', () {
      expect(blocksOf('a\n```dart\n[x](x.md)\n```\nb\n~~~\ny\n~~~\n'), ['a\n', 'b\n']);
    });

    test('closes a fence only with at least as many of the same character', () {
      expect(blocksOf('````\n```\n~~~~\n````\nafter\n'), ['after\n']);
    });

    test('reads a backtick fence whose info string has a backtick as text', () {
      expect(blocksOf('```a`\n'), ['```a`\n']);
    });

    test('skips an indented code block', () {
      expect(blocksOf('    code\n\ttab code\n\ntext\n'), ['text\n']);
    });

    test('reads an indented line that continues a paragraph as text', () {
      expect(blocksOf('text\n    more\n'), ['text\n    more\n']);
    });

    test('ends a fence that a blockquote holds when the blockquote ends', () {
      expect(blocksOf('> ```\n> code\nafter\n'), ['after\n']);
    });

    test('ends a fence that a list item holds when a line is less indented', () {
      expect(blocksOf('- ```\n  code\nafter\n'), ['after\n']);
    });
  });

  group('blockquotes', () {
    test('blanks the > markers', () {
      expect(blocksOf('> a\n> b\n'), ['  a\n  b\n']);
    });

    test('continues a paragraph lazily on a line without >', () {
      expect(blocksOf('> a\nb\n'), ['  a\nb\n']);
    });

    test('nests blockquotes', () {
      expect(blocksOf('> > a\n'), ['    a\n']);
    });

    test('skips an indented code block inside a blockquote', () {
      expect(blocksOf('>     code\n'), isEmpty);
    });
  });

  group('list items', () {
    test('makes each list item its own block', () {
      expect(blocksOf('- a\n- b\n1. c\n'), ['  a\n', '  b\n', '   c\n']);
    });

    test('keeps lines indented to the item content in the item', () {
      expect(blocksOf('- a\n\n  b\n'), ['  a\n', '  b\n']);
    });

    test('reads content indented 4 columns past the item content as code', () {
      expect(blocksOf('- a\n\n      code\n'), ['  a\n']);
    });

    test('reads content 5 or more columns after the marker as indented code', () {
      expect(blocksOf('-     code\n'), isEmpty);
    });

    test('reads list content indented 4 or more columns as text, not code', () {
      expect(blocksOf('1.  a\n\n    b\n'), ['    a\n', '    b\n']);
    });

    test('does not let an ordered item other than 1 interrupt a paragraph', () {
      expect(blocksOf('Version\n2. Configuration\n'), ['Version\n2. Configuration\n']);
    });

    test('does not let an empty item interrupt a paragraph', () {
      expect(blocksOf('a\n-\n'), ['a\n']);
    });

    test('ends an item that starts with a blank line at the next blank line', () {
      expect(blocksOf('-\n  a\n\n  b\n'), ['  a\n', '  b\n']);
      expect(blocksOf('-\n\n  b\n'), ['  b\n']);
    });

    test('reads * * * as a thematic break, not a list item', () {
      expect(blocksOf('* * *\n'), isEmpty);
    });

    test('counts a tab as reaching the next multiple of 4 columns', () {
      expect(blocksOf('-\ta\n\n\tb\n'), ['  a\n', ' b\n']);
    });
  });
}
