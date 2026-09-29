// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Every `lib/src` file is imported directly by at least one test, or is
/// listed in exactly one of [trivialDataClasses], [coveredByIntegrationTests]
/// or [untestedAllowlist].
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Files with nothing worth unit testing: constants, plain data holders, or
/// barrels of `export` directives. A test for one of these would only repeat
/// the code.
///
/// Add a file here only if it has no logic. If you are unsure, put it on
/// [untestedAllowlist] instead. Files exported from `lib/skills_lint.dart`
/// are public API and cannot be listed here.
const Set<String> trivialDataClasses = {
  // A barrel of `export` directives with no code.
  'models/sarif/models/models.dart',
  // One string constant.
  'models/sarif/sarif_constants.dart',
  // One URL constant.
  'specification_urls.dart',
};

/// Files whose behavior is best tested through a broader test, mapped to
/// that test file.
///
/// Add a file here only after checking that the named test runs it, for
/// example with `dart test --coverage`. The named test file must exist.
const Map<String, String> coveredByIntegrationTests = {
  'cutoff_excerpt.dart': 'test/description_length_limit_test.dart',
  'missing_defaults_exception.dart': 'test/api_boundary_test.dart',
  'models/sarif/models/sarif_artifact_location.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_driver.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_location.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_log.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_message.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_physical_location.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_region.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_reporting_configuration.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_result.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_rule.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_run.dart': 'test/sarif_format_test.dart',
  'models/sarif/models/sarif_tool.dart': 'test/sarif_format_test.dart',
  'models/sarif/sarif_serializer.dart': 'test/sarif_format_test.dart',
  'models/validation_result.dart': 'test/validation_result_test.dart',
  'models/validation_target.dart': 'test/api_defaults_test.dart',
  'reporters/json_reporter.dart': 'test/sarif_format_test.dart',
  'reporters/reporter.dart': 'test/sarif_format_test.dart',
  'reporters/sarif_reporter.dart': 'test/sarif_format_test.dart',
  'reporters/text_reporter.dart': 'test/reporter_error_prefix_test.dart',
  'reporters/tool_error_messages.dart': 'test/reporter_error_prefix_test.dart',
};

/// Files that need a direct test and do not have one yet.
///
/// Do not add files here; write the test instead. When a test imports one of
/// these files directly, remove it from this list. The test fails until you
/// do.
const Set<String> untestedAllowlist = {
  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/58 add unit tests.
  'suggestions/levenshtein.dart',
};

/// Matches a `lib/src` URI in a test file, as a package or relative import,
/// and captures the path below `lib/src/`.
final RegExp _srcUri = RegExp(
  r'''['"](?:package:skills_lint/src/|(?:\.\./)+lib/src/)([^'"]+)['"]''',
);

/// Matches an `export 'src/...'` directive and captures the path below `src/`.
final RegExp _srcExport = RegExp(r'''^export\s+'src/([^']+)''', multiLine: true);

const String _self = 'test/test_coverage_convention_test.dart';

void main() {
  final Set<String> sources = _libSrcFiles();
  final Set<String> untested = sources.difference(_importedByTests());
  final Set<String> integration = coveredByIntegrationTests.keys.toSet();
  final Set<String> listed = {...trivialDataClasses, ...integration, ...untestedAllowlist};

  test('every lib/src file is imported directly by a test or listed', () {
    _expectNone(
      untested.difference(listed),
      'No test imports these lib/src files directly. Add a test under test/ that imports '
      'each one (for example package:skills_lint/src/<path>):',
    );
  });

  test('untestedAllowlist only lists files that are still untested', () {
    _expectNone(
      untestedAllowlist.difference(untested),
      'Remove these entries from untestedAllowlist in $_self. A test now imports them '
      'directly, or they no longer exist:',
    );
  });

  test('trivialDataClasses and coveredByIntegrationTests list existing files', () {
    _expectNone(
      {...trivialDataClasses, ...integration}.difference(sources),
      'Remove these entries from $_self. They no longer exist under lib/src/:',
    );
  });

  test('each file is on at most one list', () {
    _expectNone({
      ...trivialDataClasses.intersection(integration),
      ...trivialDataClasses.intersection(untestedAllowlist),
      ...integration.intersection(untestedAllowlist),
    }, 'These files are on more than one list in $_self. Keep each on one list:');
  });

  test('coveredByIntegrationTests names test files that exist', () {
    _expectNone(
      {
        for (final MapEntry<String, String> e in coveredByIntegrationTests.entries)
          if (!File(e.value).existsSync()) '${e.key} -> ${e.value}',
      },
      'These test files in coveredByIntegrationTests do not exist. Point each entry at '
      'the test that exercises the file:',
    );
  });

  test('exported files are not on trivialDataClasses or untestedAllowlist', () {
    _expectNone(
      _exportedFiles().intersection({...trivialDataClasses, ...untestedAllowlist}),
      'These files are exported from lib/skills_lint.dart, so they are public API. Add a '
      'direct test, or name the test that covers them in coveredByIntegrationTests:',
    );
  });
}

void _expectNone(Set<String> found, String fix) {
  final List<String> sorted = found.toList()..sort();
  expect(sorted, isEmpty, reason: '$fix\n${sorted.join('\n')}');
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

Set<String> _exportedFiles() => {
  for (final RegExpMatch m in _srcExport.allMatches(
    File(p.join('lib', 'skills_lint.dart')).readAsStringSync(),
  ))
    m.group(1)!,
};

Iterable<File> _dartFiles(String dir) => Directory(
  dir,
).listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'));
