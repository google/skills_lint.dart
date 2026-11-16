// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/feature/markdown/inline_scanner.dart';
import 'package:skills_lint/src/feature/markdown/link_models.dart';
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';

MarkdownInlineScanner scannerFor(String text) =>
    MarkdownInlineScanner(SourceFile.fromString(text), text);

/// The span text and target of each link in [text], read as one block.
List<(String, String)> linksIn(String text, {Map<String, String> definitions = const {}}) {
  final file = SourceFile.fromString(text);
  final destinations = <String, LinkDestination>{
    for (final MapEntry<String, String> entry in definitions.entries)
      entry.key: LinkDestination(
        file.span(text.indexOf(entry.value), text.indexOf(entry.value) + entry.value.length),
        isAngleBracketed: false,
      ),
  };
  return [
    for (final MarkdownLink link in MarkdownInlineScanner(
      file,
      text,
    ).scanLinks(0, text.length, destinations))
      (link.span.text, link.target),
  ];
}

void main() {
  group('scanLinks', () {
    test('reads an inline link and its span', () {
      expect(linksIn('See [a](a.md "Title").'), [('[a](a.md "Title")', 'a.md')]);
    });

    test('reads an angle-bracketed destination without its brackets', () {
      expect(linksIn('[a](<my file.md>)'), [('[a](<my file.md>)', 'my file.md')]);
    });

    test('reads a destination with balanced parentheses', () {
      expect(linksIn('[a](a(b).md)'), [('[a](a(b).md)', 'a(b).md')]);
    });

    test('reads an image inside a link', () {
      expect(linksIn('[![b](b.png)](c.md)'), [
        ('![b](b.png)', 'b.png'),
        ('[![b](b.png)](c.md)', 'c.md'),
      ]);
    });

    test('does not read a link inside another link', () {
      expect(linksIn('[[a](a.md)](b.md)'), [('[a](a.md)', 'a.md')]);
    });

    test('skips escaped brackets and code spans', () {
      expect(linksIn(r'\[a](a.md) `[b](b.md)` [c](c.md)'), [('[c](c.md)', 'c.md')]);
    });

    test('reads full, collapsed and shortcut reference links', () {
      expect(
        linksIn('[one][Ref] [ref][] [ref] [none][missing] ref.md', definitions: {'ref': 'ref.md'}),
        [('[one][Ref]', 'ref.md'), ('[ref][]', 'ref.md'), ('[ref]', 'ref.md')],
      );
    });
  });

  group('parseDefinition', () {
    test('reads the label, destination and end of a definition', () {
      const text = '[My  Ref]: docs/guide.md "Guide"\nnext';
      final LinkDefinition? definition = scannerFor(text).parseDefinition(0, text.length);
      expect(definition?.label, 'my ref');
      expect(definition?.destination.text, 'docs/guide.md');
      expect(definition?.end, text.indexOf('next'));
    });

    test('reads a destination and a title on the following lines', () {
      const text = '[ref]:\n  guide.md\n  "Guide"\n';
      final LinkDefinition? definition = scannerFor(text).parseDefinition(0, text.length);
      expect(definition?.destination.text, 'guide.md');
      expect(definition?.end, text.length);
    });

    test('returns null for text after the destination', () {
      const text = '[ref]: guide.md extra\n';
      expect(scannerFor(text).parseDefinition(0, text.length), isNull);
    });

    test('returns null for a label longer than maxLinkLabelLength', () {
      final text = '[${'a' * (maxLinkLabelLength + 1)}]: guide.md\n';
      expect(scannerFor(text).parseDefinition(0, text.length), isNull);
      final fits = '[${'a' * maxLinkLabelLength}]: guide.md\n';
      expect(scannerFor(fits).parseDefinition(0, fits.length), isNotNull);
    });
  });

  test('normalizeLinkLabel trims, collapses whitespace and folds case', () {
    expect(normalizeLinkLabel('  Foo \t\n Bar  '), 'foo bar');
    expect(normalizeLinkLabel('STRASSE'), normalizeLinkLabel('Straße'));
  });
}
