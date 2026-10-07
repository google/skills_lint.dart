// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/repo_paths.dart';

void main() {
  test('packageVersion matches the version in pubspec.yaml', () {
    final pubspec = File(p.join(packageRoot, 'pubspec.yaml'));
    final Object? version = (loadYaml(pubspec.readAsStringSync()) as YamlMap)['version'];
    expect(
      packageVersion,
      equals(version),
      reason:
          '`skills_lint --version` prints packageVersion from lib/src/version.dart, which '
          'must match the version in pubspec.yaml. Update both to the same version.',
    );
  });
}
