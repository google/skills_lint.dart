// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Files under `lib/src/` that no test imports directly. They are reached
/// only through the `package:skills_lint/skills_lint.dart` barrel.
///
/// This list only shrinks. When a test imports one of these files directly,
/// remove it from the list. Do not add new files; add a test instead.
const Set<String> untestedAllowlist = {
  'cutoff_excerpt.dart',
  'missing_defaults_exception.dart',
  'models/sarif/models/models.dart',
  'models/sarif/models/sarif_artifact_location.dart',
  'models/sarif/models/sarif_driver.dart',
  'models/sarif/models/sarif_location.dart',
  'models/sarif/models/sarif_log.dart',
  'models/sarif/models/sarif_message.dart',
  'models/sarif/models/sarif_physical_location.dart',
  'models/sarif/models/sarif_region.dart',
  'models/sarif/models/sarif_reporting_configuration.dart',
  'models/sarif/models/sarif_result.dart',
  'models/sarif/models/sarif_rule.dart',
  'models/sarif/models/sarif_run.dart',
  'models/sarif/models/sarif_tool.dart',
  'models/sarif/sarif_serializer.dart',
  'models/validation_result.dart',
  'models/validation_target.dart',
  'reporters/json_reporter.dart',
  'reporters/reporter.dart',
  'reporters/sarif_reporter.dart',
  'reporters/text_reporter.dart',
  'suggestions/levenshtein.dart',
};

/// Matches a `lib/src` URI in a test file, as a package or relative import,
/// and captures the path below `lib/src/`.
final RegExp _srcUri = RegExp(
  r'''['"](?:package:skills_lint/src/|(?:\.\./)+lib/src/)([^'"]+)['"]''',
);

/// Every `lib/src` file is imported directly by at least one test.
void main() {
  final Set<String> sources = _libSrcFiles();
  final Set<String> imported = _importedByTests();

  test('every lib/src file is imported directly by a test', () {
    final List<String> untested =
        (sources.difference(imported).difference(untestedAllowlist).toList()..sort());
    expect(
      untested,
      isEmpty,
      reason:
          'No test imports these lib/src files directly. Add a test under test/ that '
          'imports each one (for example package:skills_lint/src/<path>):\n'
          '${untested.join('\n')}',
    );
  });

  test('untestedAllowlist only lists files that are still untested', () {
    final List<String> stale = (untestedAllowlist.difference(sources.difference(imported)).toList()
      ..sort());
    expect(
      stale,
      isEmpty,
      reason:
          'Remove these entries from untestedAllowlist in '
          'test/test_coverage_convention_test.dart. A test now imports them directly, '
          'or they no longer exist:\n${stale.join('\n')}',
    );
  });
}

/// Paths below `lib/src/`, with `/` separators, excluding generated files.
Set<String> _libSrcFiles() {
  final String root = p.join('lib', 'src');
  return {
    for (final File f in _dartFiles(root))
      if (!f.path.endsWith('.g.dart')) p.posix.joinAll(p.split(p.relative(f.path, from: root))),
  };
}

Set<String> _importedByTests() => {
  for (final File f in _dartFiles('test'))
    for (final RegExpMatch m in _srcUri.allMatches(f.readAsStringSync())) m.group(1)!,
};

Iterable<File> _dartFiles(String dir) => Directory(
  dir,
).listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'));
