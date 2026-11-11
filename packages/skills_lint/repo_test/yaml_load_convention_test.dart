// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/models/convention_violation.dart';
import 'src/models/source.dart';
import 'src/package_directories.dart';
import 'src/source_conventions.dart';
import 'src/yaml_loading.dart';

/// Checks that shipped code parses YAML only through `YamlLimits`, so every
/// document skills_lint reads is bounded before a caller sees its value.
///
/// `src/yaml_loading.dart` says why the rule exists, and
/// `checkers/yaml_loading_test.dart` pins which references it reports. Only
/// `bin/` and `lib/` are scanned: tests and the release scripts read YAML
/// that the repository itself controls.
void main() {
  test('no shipped file outside the allowlist parses YAML with package:yaml directly', () {
    final List<ConventionViolation> violations = [
      for (final Source source in parseDirectories(shippedDirectories))
        if (!_allowed.containsKey(source.path)) ...findRawYamlLoads(source),
    ];
    expectNoViolations(violations, fix: _fix);
  });
}

/// Files that may call `package:yaml`'s loaders, keyed by package-relative
/// path, each with its reason.
const Map<String, String> _allowed = {
  'lib/src/yaml_limits.dart': 'Defines YamlLimits, which wraps loadYamlNode with the limits.',
};

const String _fix =
    'Parse with YamlLimits.loadYaml from lib/src/yaml_limits.dart, or '
    'YamlLimits.loadFrontmatter for SKILL.md frontmatter.';
