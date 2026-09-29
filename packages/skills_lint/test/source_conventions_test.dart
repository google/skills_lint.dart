// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/models/source.dart';
import 'src/models/violation.dart';
import 'src/source_conventions.dart';

/// Source conventions that reviewers enforce, checked across the package.
///
/// Each check runs a detector from `src/source_conventions.dart` over the
/// package's Dart files. `source_convention_detectors_test.dart` pins what
/// each detector reports on small snippets.
void main() {
  group('repository', () {
    late List<Source> sources;

    setUpAll(() {
      sources = parseDirectories(_scannedDirectories);
    });

    Iterable<Source> under(List<String> directories) =>
        sources.where((source) => directories.any((d) => source.path.startsWith('$d/')));

    test('map keys and indices under lib/src/models/ are not string literals', () {
      final List<Violation> violations = [];
      for (final Source source in under(const ['lib/src/models'])) {
        violations.addAll(findStringLiteralKeys(source));
      }
      expectNoViolations(violations, fix: _stringLiteralKeyFix);
    });

    test('no string literal of $minSharedLiteralLength+ characters is repeated across lib/', () {
      expectNoViolations(findSharedLiterals(under(const ['lib'])), fix: _sharedLiteralFix);
    });

    test('no operator ==, hashCode, or toString overrides', () {
      final List<Violation> violations = [];
      for (final source in sources) {
        final Set<String> allowed = _allowedOverrides[source.path] ?? const {};
        violations.addAll(findForbiddenOverrides(source, allowed: allowed));
      }
      expectNoViolations(violations, fix: _forbiddenOverrideFix);
    });

    test('no constant in bin/ or lib/ is declared as an alias of another constant', () {
      expectNoViolations(findConstAliases(under(const ['bin', 'lib'])), fix: _constAliasFix);
    });
  });
}

/// Directories whose Dart files the checks read.
///
/// `evals/test_data/` is left out because its Dart files are fixtures that
/// are written to fail review on purpose.
const List<String> _scannedDirectories = ['benchmark', 'bin', 'example', 'lib', 'test'];

/// Overrides that are allowed, keyed by package-relative path.
///
/// `ConfigSerializer` wraps a `StringBuffer`, and its `toString()` returns
/// the buffer contents in the same way `StringBuffer.toString()` does.
const Map<String, Set<String>> _allowedOverrides = {
  'lib/src/config_serializer.dart': {'toString'},
};

const String _stringLiteralKeyFix =
    'Declare the key as a `static const String` on the model class that owns '
    "it (for example `static const String keyStartLine = 'startLine';`) and "
    'use that constant wherever the key is read or written.';

const String _sharedLiteralFix =
    'Declare the text once, in the library that owns the message, and '
    'reference it from every file. If the text interpolates values, move it '
    'into a function that takes those values. Do not declare a second '
    'constant that aliases the first; the const-alias check rejects that.';

/// Built from [_allowedOverrides] so the message and the allowlist agree.
final String _forbiddenOverrideFix = () {
  final List<String> allowed = [
    for (final MapEntry(key: path, value: names) in _allowedOverrides.entries)
      for (final name in names) '`$name()` in $path',
  ];
  return 'Remove the override. The only allowed overrides are ${allowed.join(', ')}.';
}();

const String _constAliasFix =
    'Delete the second constant and reference the original constant directly.';
