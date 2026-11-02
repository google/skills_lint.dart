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
  // last release, which is the newest version with assets to download. The
  // README links to /releases/latest, which never serves a prerelease, so a
  // prerelease keeps the last release too.
  test('README install examples name the newest released CHANGELOG version', () {
    final String changelog = File(p.join(packageRoot, 'CHANGELOG.md')).readAsStringSync();
    final String? released = _newestRelease(changelog);
    if (released == null) {
      fail('CHANGELOG.md has no "## <version>" heading for a release that is not a prerelease.');
    }
    final String readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
    for (final RegExp line in _installVersionLines) {
      expect(
        _versions(readme, line),
        allOf(isNotEmpty, everyElement(released)),
        reason:
            'README.md lines matching ${line.pattern} must name $released, the newest release '
            'in CHANGELOG.md that is not a prerelease. See RELEASING.md.',
      );
    }
  });

  group('_newestRelease', () {
    test('skips -wip and other prerelease headings', () {
      expect(_newestRelease('## 1.1.0-wip\n\n## 1.0.0-dev.1\n\n- a\n\n## 0.9.0\n\n- b\n'), '0.9.0');
    });
    test('skips the -wip version of a build', () {
      expect(_newestRelease('## 1.0.0+1-wip\n\n## 1.0.0\n\n- a\n'), '1.0.0');
    });
    test('reads a release with a build number and Windows line endings', () {
      expect(_newestRelease('## 1.0.0+1\r\n\r\n- a\r\n'), '1.0.0+1');
    });
    test('is null without a release heading', () {
      expect(_newestRelease('## 0.1.0-wip\n\n- a\n'), isNull);
    });
  });

  group('_versions', () {
    test('reads each install line, including one with a trailing comment', () {
      const readme =
          '  skills_lint: ^1.0.0\n'
          '  skills_lint: ^0.5.0 # older pin\n'
          'VERSION="1.0.0"  # the release\n'
          '  skills: ^1.0.0\n';
      final [RegExp pin, RegExp download] = _installVersionLines;
      expect(_versions(readme, pin), ['1.0.0', '0.5.0']);
      expect(_versions(readme, download), ['1.0.0']);
    });
  });
}

/// The README lines that name a skills_lint version to install: the
/// `skills_lint: ^<version>` dependency and the direct download's
/// `VERSION="<version>"`. Each captures the version and allows a trailing
/// `# comment`.
final List<RegExp> _installVersionLines = [
  RegExp(r'^\s*skills_lint: \^(\S+)(?:\s+#.*)?\s*$', multiLine: true),
  RegExp(r'^VERSION="([^"]*)"(?:\s+#.*)?\s*$', multiLine: true),
];

/// The versions that the [line] pattern captures in [readme].
List<String> _versions(String readme, RegExp line) => [
  for (final Match m in line.allMatches(readme)) m[1]!,
];

/// The newest `## <version>` heading in [changelog] that is not a
/// prerelease: one without a `-` suffix such as `-wip` or `-dev.1`.
///
/// Is `null` if there is no such heading.
String? _newestRelease(String changelog) {
  for (final Match m in RegExp(r'^## (\S+)\s*$', multiLine: true).allMatches(changelog)) {
    final String version = m[1]!;
    if (!version.contains('-')) {
      return version;
    }
  }
  return null;
}
