// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/yaml_anchor_scanner.dart';
import 'package:test/test.dart';

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
      ('a document with no anchors', 'name: x\ndescription: y\nmetadata:\n  k: [1, 2]\n'),
    ]) {
      test(description, () {
        expect(YamlAnchorScanner.firstAnchorOrAlias(yaml), isNull);
      });
    }
  });
}
