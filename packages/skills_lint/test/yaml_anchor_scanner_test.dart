// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/yaml_anchor_scanner.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('YamlAnchorScanner finds', () {
    for (final (String description, String yaml, String token) in [
      ('an anchor on a value', 'a: &shared text\nb: c\n', '&shared'),
      ('an alias as a value', 'a: b\nc: *shared\n', '*shared'),
      ('an alias as a mapping key', '*key : value\n', '*key'),
      ('an alias as an explicit key', '? *key\n: value\n', '*key'),
      ('a merge key', 'base: x\n<<: *base\n', '*base'),
      ('an alias in a sequence entry', 'list:\n  - a\n  - *item\n', '*item'),
      ('an alias in a nested sequence', 'list:\n  - - *item\n', '*item'),
      ('an alias on the line after its key', 'a:\n  *item\n', '*item'),
      ('an anchor after a tag', 'a: !!str &tagged text\n', '&tagged'),
      ('an alias in a flow sequence', 'a: [x, *item]\n', '*item'),
      ('an alias in a flow mapping', 'a: {k: *item}\n', '*item'),
      ('an alias after a quoted flow key', 'a: {"k":*item}\n', '*item'),
      ('an alias after a multi-line quoted value', 'a: "one\n  two"\nb: *item\n', '*item'),
      ('an alias after a block scalar ends', 'a: |\n  *bold*\nb: *item\n', '*item'),
      (
        'an alias in a sibling key after a block scalar in a sequence',
        '- key: |\n    text\n  other: *item\n',
        '*item',
      ),
      ('an alias after a plain value on the line before', 'a: text\nb: *item\n', '*item'),
      ('an alias as a value that starts with a star', 'description: *Important*\n', '*Important*'),
      (
        'a key after an empty block scalar in a compact sequence entry',
        'name: x\nl:\n- k: |\n  j: &a [1]\n  *a : v\n',
        '&a',
      ),
      (
        'a key after an empty folded scalar in a nested sequence',
        'l:\n  - k: >\n    &a j: 1\n',
        '&a',
      ),
      ('a value after a block scalar explicit key', '? |\n  text\n: *a\n', '*a'),
      ('an anchor after a byte order mark', '\uFEFF&a name: x\n', '&a'),
      ('an anchor after a lone carriage return', 'name: x\r&a k: v\r', '&a'),
      ('an anchor after a document marker', '--- &a [x]\n', '&a'),
      ('a key after an explicit key in a sequence entry', 'l:\n- ? a\n  : b\n  j: &a [1]\n', '&a'),
      ('a key after a plain explicit key in a sequence entry', 'l:\n- ? a\n  j: &a [1]\n', '&a'),
      ('a key after nested explicit keys', 'l:\n- ? ? a\n    : b\n  : c\n  j: &a [1]\n', '&a'),
    ]) {
      test(description, () {
        expect(YamlAnchorScanner.firstAnchorOrAlias(yaml)?.token, token);
      });
    }

    test('the offset of the token', () {
      const yaml = 'name: x\nb: *item\n';
      expect(YamlAnchorScanner.firstAnchorOrAlias(yaml)?.offset, yaml.indexOf('*item'));
    });
  });

  group('YamlAnchorScanner ignores', () {
    for (final (String description, String yaml) in [
      ('stars inside plain text', 'description: Use *bold* text & more.\n'),
      ('an ampersand in a plain URL', 'homepage: https://example.com/?a=1&b=2\n'),
      ('stars inside double quotes', 'description: "*bold* and &amp;"\n'),
      ('stars inside single quotes', "description: '*bold* isn''t &x'\n"),
      ('an ampersand in a quoted URL', 'url: "https://example.com/?a=1&b=2"\n'),
      ('a comment line with a star', '# comment with *star\nname: x\n'),
      ('a trailing comment with a star', 'name: x # comment with *star &amp\n'),
      ('a literal block scalar', 'description: |\n  *bold* line\n  &more\nname: x\n'),
      ('a folded block scalar', 'description: >-\n  *bold*\n\n  &more\nname: x\n'),
      (
        'a multi-line plain scalar',
        'description: Long text\n  *emphasis* here\n  & more\nname: x\n',
      ),
      ('a multi-line double-quoted scalar', 'description: "one\n  *two* \\" &three"\nname: x\n'),
      ('plain text in a flow sequence', 'tags: [a & b, c*d]\n'),
      ('a star inside a plain key', 'a*b: c\n'),
      ('a block scalar with an indentation indicator', 'a: |2\n    x\n  b: *i\nc: d\n'),
      ('an indented block scalar in a sequence entry', '- k: |2\n      x\n    *i\n- y\n'),
      ('a document with no anchors', 'name: x\ndescription: y\nmetadata:\n  k: [1, 2]\n'),
    ]) {
      test(description, () {
        expect(YamlAnchorScanner.firstAnchorOrAlias(yaml), isNull);
      });
    }
  });

  test('YamlAnchorScanner finds every alias that package:yaml resolves', () {
    final (:int aliased, :List<String> missed) = _scanGeneratedAliases();

    expect(aliased, greaterThan(100), reason: 'The generator should build many aliased documents.');
    expect(missed, isEmpty, reason: 'Missed aliases in:\n${missed.join('\n---\n')}');
  });
}

/// Scans generated documents that use an alias, and counts them along with
/// the ones the scanner missed.
///
/// The documents combine compact `-`, `?` and `:` nesting, scalars of each
/// style, and keys at each indentation. Whenever package:yaml loads a
/// document and shares a node between two places, the document used an
/// alias, so the scanner must report something.
({int aliased, List<String> missed}) _scanGeneratedAliases() {
  const owners = ['', '- ', '? ', '- ? ', '- - ', 'k: ', '- k: ', '- ? k: ', '? - '];
  const scalars = ['a', '"a"', "'a'", '|\n', '>-\n', '|2\n', ''];
  const keys = ['j: &a [1]\n{i}m: *a\n', 'j: &a [1]\n{i}*a : v\n', '? *a\n{i}: v\n'];
  final missed = <String>[];
  var aliased = 0;
  for (final owner in owners) {
    for (final scalar in scalars) {
      for (final key in keys) {
        for (var indent = 0; indent <= 6; indent++) {
          final String i = ' ' * indent;
          final String yaml = 'name: x\nl:\n$owner$scalar\n$i${key.replaceAll('{i}', i)}'
              .replaceFirst('$scalar\n\n', '$scalar\n');
          if (!_hasSharedNode(yaml)) {
            continue;
          }
          aliased++;
          if (YamlAnchorScanner.firstAnchorOrAlias(yaml) == null) {
            missed.add(yaml);
          }
        }
      }
    }
  }
  return (aliased: aliased, missed: missed);
}

/// Whether [yaml] loads and holds one collection node in two places.
bool _hasSharedNode(String yaml) {
  final YamlNode root;
  try {
    root = loadYamlNode(yaml);
  } on YamlException {
    return false;
  }
  final seen = Set<YamlNode>.identity();
  bool visit(YamlNode node) {
    if (node is YamlScalar) {
      return false;
    }
    if (!seen.add(node)) {
      return true;
    }
    final Iterable<YamlNode> children = switch (node) {
      YamlMap(:final Map<dynamic, YamlNode> nodes) => [
        ...nodes.keys.whereType<YamlNode>(),
        ...nodes.values,
      ],
      YamlList(:final List<YamlNode> nodes) => nodes,
      _ => const [],
    };
    return children.any(visit);
  }

  return visit(root);
}
