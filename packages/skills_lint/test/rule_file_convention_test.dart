// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Matches a top-level (unindented) class, enum, mixin, or extension type
/// declaration, with any class modifiers, and captures its name.
final RegExp _topLevelType = RegExp(
  r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
  r'(?:class|enum|mixin|extension\s+type)\s+(?:const\s+)?([A-Za-z_$][\w$]*)',
  multiLine: true,
);

/// Each file in `lib/src/rules/` declares at most one public type.
void main() {
  test('each rule file declares at most one public type', () {
    final problems = <String>[];
    for (final File file in _ruleFiles()) {
      final List<String> public = _publicTypes(file.readAsStringSync());
      if (public.length > 1) {
        problems.add('${p.relative(file.path)}: ${public.join(', ')}');
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'These rule files declare more than one public type. Keep the rule class '
          'and move each other type to its own file outside lib/src/rules/, or make it '
          'private with a leading underscore:\n${problems.join('\n')}',
    );
  });
}

List<File> _ruleFiles() =>
    Directory(
        p.join('lib', 'src', 'rules'),
      ).listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));

List<String> _publicTypes(String source) => [
  for (final RegExpMatch m in _topLevelType.allMatches(source))
    if (!m.group(1)!.startsWith('_')) m.group(1)!,
];
