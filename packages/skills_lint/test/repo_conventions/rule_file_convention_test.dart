// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Each file in `lib/src/rules/` declares at most one public type.
///
/// Why this matters:
/// - One rule per file, so a rule is found by its file name.
/// - `RuleRegistry` maps 1:1 to the files in `lib/src/rules/`.
/// - Helper types either stay private to the rule file, or move to their own
///   file with their own tests.
///
/// Revisit this if a rule needs a public companion type that configuration
/// or other packages use, such as a parameter type exported for callers.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/models/source.dart';
import '../src/source_conventions.dart';

void main() {
  test('each rule file declares at most one public type', () {
    final problems = <String>[];
    for (final Source source in parseDirectories([p.join('lib', 'src', 'rules')])) {
      final List<String> public = _publicTypes(source);
      if (public.length > 1) {
        problems.add('${source.path}: ${public.join(', ')}');
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

/// Returns the public top-level class, enum, mixin and extension type names
/// in [source].
List<String> _publicTypes(Source source) => [
  for (final CompilationUnitMember member in source.unit.declarations)
    if (_typeName(member) case final String name when !name.startsWith('_')) name,
];

String? _typeName(CompilationUnitMember member) => switch (member) {
  final ClassDeclaration type => type.namePart.typeName.lexeme,
  final EnumDeclaration type => type.namePart.typeName.lexeme,
  final MixinDeclaration type => type.name.lexeme,
  final ExtensionTypeDeclaration type => type.primaryConstructor.typeName.lexeme,
  _ => null,
};
