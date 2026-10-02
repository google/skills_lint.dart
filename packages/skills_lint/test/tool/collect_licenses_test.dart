// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/collect_licenses.dart';

/// A `dart pub deps --json` package entry.
Map<String, Object?> _package(String name, List<String> deps, {List<String> dev = const []}) => {
  'name': name,
  'dependencies': [...deps, ...dev],
  'directDependencies': deps,
  'devDependencies': dev,
};

/// Matches the heading of each section in [formatNotices] output: the first
/// line of the output, or the line after a separator.
final RegExp _heading = RegExp('(?:^|${'-' * 80}\n\n)(.+) license:\n\n');

void main() {
  group('runtimeDependencies', () {
    test('follows dependencies transitively and leaves out dev dependencies', () {
      final List<String> deps = runtimeDependencies({
        'packages': [
          _package('skills_lint', ['yaml', 'args'], dev: ['test']),
          _package('yaml', ['source_span', 'collection']),
          _package('source_span', ['collection']),
          _package('collection', []),
          _package('args', []),
          _package('test', ['test_api', 'collection']),
          _package('test_api', []),
        ],
      });
      expect(deps, ['args', 'collection', 'source_span', 'yaml']);
    });

    test('ignores other packages in the workspace', () {
      final List<String> deps = runtimeDependencies({
        'packages': [
          _package('skills_lint_workspace', []),
          _package('api_boundary_runner', ['skills_lint', 'logging']),
          _package('skills_lint', ['path']),
          _package('path', []),
          _package('logging', []),
        ],
      });
      expect(deps, ['path']);
    });

    test('throws when skills_lint is not listed', () {
      expect(
        () => runtimeDependencies({
          'packages': [_package('other', [])],
        }),
        throwsA(
          isA<LicenseCollectionException>().having(
            (e) => e.message,
            'message',
            contains('skills_lint'),
          ),
        ),
      );
    });

    test('throws when a dependency is not listed', () {
      expect(
        () => runtimeDependencies({
          'packages': [
            _package('skills_lint', ['yaml']),
          ],
        }),
        throwsA(
          isA<LicenseCollectionException>().having((e) => e.message, 'message', contains('yaml')),
        ),
      );
    });
  });

  group('formatNotices', () {
    test('lists components that share a license text under one copy of it', () {
      final String notices = formatNotices([
        (component: 'skills_lint', text: 'BSD text\n'),
        (component: 'Dart SDK', text: 'SDK text'),
        (component: 'args', text: 'BSD text'),
        (component: 'path', text: 'BSD text\r\n'),
        (component: 'yaml', text: 'MIT text'),
      ]);
      expect(_heading.allMatches(notices).map((m) => m.group(1)), [
        'skills_lint, args and path',
        'Dart SDK',
        'yaml',
      ]);
      expect(
        notices,
        'skills_lint, args and path license:\n\nBSD text\n\n${'-' * 80}\n\n'
        'Dart SDK license:\n\nSDK text\n\n${'-' * 80}\n\n'
        'yaml license:\n\nMIT text\n',
      );
    });
  });

  group('files', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('collect_licenses_test.');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    String write(String relativePath, String contents) {
      final file = File(p.joinAll([tempDir.path, ...p.posix.split(relativePath)]));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
      return file.path;
    }

    group('findLicenseFile', () {
      test('prefers the shortest matching name', () {
        write('LICENSE.md', 'markdown');
        write('LICENSE', 'plain');
        write('README.md', 'readme');
        expect(findLicenseFile(tempDir.path)?.readAsStringSync(), 'plain');
      });

      test('finds COPYING', () {
        write('COPYING', 'gpl');
        expect(findLicenseFile(tempDir.path)?.readAsStringSync(), 'gpl');
      });

      test('returns null without a license file', () {
        write('README.md', 'readme');
        expect(findLicenseFile(tempDir.path), isNull);
        expect(findLicenseFile(p.join(tempDir.path, 'missing')), isNull);
      });
    });

    group('readSdkLicense', () {
      test('reads LICENSE in the SDK directory', () {
        write('dart-sdk/LICENSE', 'sdk');
        expect(readSdkLicense(p.join(tempDir.path, 'dart-sdk')), 'sdk');
      });

      test('reads LICENSE in the directory above, as Homebrew installs it', () {
        write('LICENSE', 'homebrew');
        Directory(p.join(tempDir.path, 'libexec')).createSync();
        expect(readSdkLicense(p.join(tempDir.path, 'libexec')), 'homebrew');
      });

      test('throws without a LICENSE file', () {
        final String sdkDir = p.join(tempDir.path, 'dart-sdk');
        Directory(sdkDir).createSync();
        expect(() => readSdkLicense(sdkDir), throwsA(isA<LicenseCollectionException>()));
      });
    });

    test('findPackageConfig finds the workspace package config above the package', () {
      final String config = write('.dart_tool/package_config.json', '{}');
      final String packageDir = p.join(tempDir.path, 'packages', 'skills_lint');
      Directory(packageDir).createSync(recursive: true);
      expect(p.equals(findPackageConfig(packageDir).path, config), isTrue);
    });

    test('packageRoots resolves relative root URIs against the package config file', () {
      final String config = write('.dart_tool/package_config.json', '{}');
      final String pubCache = p.join(tempDir.path, 'pub-cache', 'yaml-3.1.4');
      final Map<String, String> roots = packageRoots({
        'packages': [
          {'name': 'skills_lint', 'rootUri': '../packages/skills_lint/', 'packageUri': 'lib/'},
          {'name': 'yaml', 'rootUri': Uri.directory(pubCache).toString(), 'packageUri': 'lib/'},
        ],
      }, File(config).uri);
      expect(roots.keys, ['skills_lint', 'yaml']);
      expect(
        p.equals(roots['skills_lint']!, p.join(tempDir.path, 'packages', 'skills_lint')),
        isTrue,
        reason: 'skills_lint root: ${roots['skills_lint']}',
      );
      expect(p.equals(roots['yaml']!, pubCache), isTrue, reason: 'yaml root: ${roots['yaml']}');
    });
  });

  group('this package', () {
    final String sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));

    test('every file in the Dart runtime licenses directory is listed', () {
      final Set<String> files = {
        for (final File file in Directory(
          p.joinAll(p.url.split(dartRuntimeLicensesDir)),
        ).listSync().whereType<File>())
          p.basename(file.path),
      }..remove('README.md');
      expect(files, unorderedEquals(dartRuntimeLicenseFiles.values));
    });

    test('notices cover skills_lint, the Dart SDK and runtime dependencies only', () async {
      final String notices = await collectLicenses(
        packageDir: Directory.current.path,
        sdkDir: sdkDir,
      );
      final Set<String> components = {
        for (final RegExpMatch match in _heading.allMatches(notices))
          ...match.group(1)!.split(RegExp(', | and ')),
      };
      expect(
        components,
        containsAll([
          'skills_lint',
          'Dart SDK',
          for (final String component in dartRuntimeLicenseFiles.keys)
            '$component (in the Dart runtime)',
          'args',
          'path',
          'yaml',
        ]),
      );
      expect(
        components.intersection({'analyzer', 'test', 'test_process', 'coverage', 'build_runner'}),
        isEmpty,
        reason: 'Dev dependencies are not compiled into the executable. Components: $components',
      );
    });

    test('the script writes the notices to --output', () async {
      final String output = p.join(
        Directory.systemTemp.createTempSync('collect_licenses_test.').path,
        'LICENSE',
      );
      addTearDown(() => Directory(p.dirname(output)).deleteSync(recursive: true));
      final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
        'run',
        p.join('tool', 'collect_licenses.dart'),
        '--output',
        output,
      ]);
      expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect(File(output).readAsStringSync(), startsWith('skills_lint license:\n'));
    });
  });
}
