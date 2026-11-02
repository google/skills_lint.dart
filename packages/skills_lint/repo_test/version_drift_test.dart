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

  // pub.dev publishes the README of each release, so a release pull request
  // sets these lines to the version it releases. A -wip version keeps the
  // last release, which is the newest version with assets to download.
  test('README install examples name the newest released CHANGELOG version', () {
    final String changelog = File(p.join(packageRoot, 'CHANGELOG.md')).readAsStringSync();
    final String released = RegExp(r'^## (\S+)\s*$', multiLine: true)
        .allMatches(changelog)
        .map((Match m) => m[1]!)
        .firstWhere((String version) => !version.endsWith('-wip'));
    final String readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
    for (final line in [
      RegExp(r'^\s*skills_lint: \^(\S+)\s*$', multiLine: true),
      RegExp(r'^VERSION="([^"]*)"\s*$', multiLine: true),
    ]) {
      final List<String> versions = [for (final Match m in line.allMatches(readme)) m[1]!];
      expect(
        versions,
        allOf(isNotEmpty, everyElement(released)),
        reason:
            'README.md lines matching ${line.pattern} must name $released, the newest released '
            'version in CHANGELOG.md. See RELEASING.md.',
      );
    }
  });
}
