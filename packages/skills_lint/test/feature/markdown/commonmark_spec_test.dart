// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Checks markdownLinksIn against the examples of the CommonMark specification,
// which package:markdown ships as tool/common_mark_tests.json.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/feature/markdown/markdown_links.dart';
import 'package:test/test.dart';

/// Sections whose links are raw HTML or autolinks, which skills_lint does not
/// read.
const _unsupportedSections = {
  'Autolinks',
  'Raw HTML',
  'HTML blocks',
  'Entity and numeric character references',
};

/// Examples where the number of links differs from the specification's HTML.
const _knownDifferences = {
  // Raw HTML and autolinks outside the unsupported sections.
  20, 21, 344, 346, 475, 476, 477, 480, 481, 524, 536, 642, 643,
  // A link inside an image's text renders as plain text, but is reported.
  520, 574, 575,
};

final RegExp _htmlLinkPattern = RegExp('<(?:a|img) [^>]*?(?:href|src)="');

typedef _Example = ({int number, String section, String markdown, int linkCount});

Future<List<_Example>> _loadExamples() async {
  final Uri? libUri = await Isolate.resolvePackageUri(Uri.parse('package:markdown/markdown.dart'));
  final String path = p.join(
    p.dirname(p.dirname(libUri!.toFilePath())),
    'tool',
    'common_mark_tests.json',
  );
  final examples = jsonDecode(File(path).readAsStringSync()) as List<Object?>;
  return [
    for (final Map<String, Object?> example in examples.cast<Map<String, Object?>>())
      if (!_unsupportedSections.contains(example['section']))
        (
          number: example['example']! as int,
          section: example['section']! as String,
          markdown: example['markdown']! as String,
          linkCount: _htmlLinkPattern.allMatches(example['html']! as String).length,
        ),
  ];
}

void main() {
  late List<_Example> examples;
  setUpAll(() async => examples = await _loadExamples());

  test('finds as many links as the specification renders', () {
    final List<String> mismatches = [
      for (final _Example example in examples)
        if (!_knownDifferences.contains(example.number) &&
            markdownLinksIn(example.markdown).length != example.linkCount)
          '#${example.number} (${example.section})',
    ];
    expect(mismatches, isEmpty);
  });

  test('finds the same links inside blockquotes and list items, and none in indented code', () {
    expect([for (final _Example example in examples) ..._nestingFailures(example)], isEmpty);
  });
}

/// How [example] fails when its lines are nested in an indented code block,
/// a blockquote and a list item. Examples whose links this package does not
/// read alone, or that hold tabs, are skipped.
List<String> _nestingFailures(_Example example) {
  final String markdown = example.markdown;
  if (example.linkCount == 0 ||
      markdown.contains('\t') ||
      markdownLinksIn(markdown).length != example.linkCount) {
    return const [];
  }
  final List<String> lines = markdown.split('\n')..removeLast();
  return [
    if (markdownLinksIn(_nest(lines, '    ')).isNotEmpty) '#${example.number} in indented code',
    if (markdownLinksIn(_nest(lines, '> ')).length != example.linkCount)
      '#${example.number} in a blockquote',
    if (markdownLinksIn(_nest(lines, '   ', firstPrefix: '1. ')).length != example.linkCount)
      '#${example.number} in a list item',
  ];
}

/// A paragraph followed by [lines], each after [prefix], with [firstPrefix]
/// before the first line when given.
String _nest(List<String> lines, String prefix, {String? firstPrefix}) {
  final List<String> nested = [
    for (final (int i, String line) in lines.indexed)
      '${i == 0 ? firstPrefix ?? prefix : prefix}$line',
  ];
  return 'Intro.\n\n${nested.join('\n')}\n';
}
