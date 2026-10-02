// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Writes the license notices that ship with the compiled `skills_lint`
/// executable.
///
/// The notices cover skills_lint, the Dart SDK, the third-party code in the
/// Dart runtime, and every package that skills_lint depends on outside
/// `dev_dependencies`, because `dart compile exe` compiles all of them into
/// the executable. Components that share a license text are listed under one
/// copy of it.
///
/// Run it from `packages/skills_lint` after `dart pub get`:
///
/// ```sh
/// dart run tool/collect_licenses.dart --output LICENSE
/// ```
///
/// It exits with code 1, and writes nothing, if a package has no license file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const String _outputOption = 'output';

/// The package whose executable the notices are for.
const String rootPackage = 'skills_lint';

/// The heading for the Dart SDK's license in the notices.
const String sdkNoticeName = 'Dart SDK';

/// The directory, relative to the package root, that holds the licenses of
/// the third-party code in the Dart runtime. Its `README.md` gives the source
/// of each file.
const String dartRuntimeLicensesDir = 'tool/dart_runtime_licenses';

/// The third-party components of the Dart runtime, each with the file in
/// [dartRuntimeLicensesDir] that holds its license.
const Map<String, String> dartRuntimeLicenseFiles = {
  'BoringSSL': 'boringssl.txt',
  'double-conversion': 'double-conversion.txt',
  'ICU': 'icu.txt',
  'Perfetto': 'perfetto.txt',
  'zlib': 'zlib.txt',
};

/// Matches the names of license files, such as `LICENSE`, `LICENSE.md` and
/// `COPYING`. This is the pattern that `package:cli_pkg` uses.
final RegExp _licenseFileName = RegExp(
  r'^(([a-zA-Z0-9]+[-_])?(LICENSE|COPYING)|UNLICENSE)(\..*)?$',
);

/// One license text and the component it applies to.
typedef LicenseNotice = ({String component, String text});

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(_outputOption, mandatory: true, help: 'The file to write the notices to.');
  final String output;
  try {
    output = parser.parse(arguments).option(_outputOption)!;
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exitCode = 64;
    return;
  }
  try {
    final String notices = await collectLicenses(
      packageDir: Directory.current.path,
      sdkDir: p.dirname(p.dirname(Platform.resolvedExecutable)),
    );
    File(output).writeAsStringSync(notices);
  } on LicenseCollectionException catch (e) {
    stderr.writeln('collect_licenses: error: ${e.message}');
    exitCode = 1;
  }
}

/// Thrown when a license notice can't be collected.
class LicenseCollectionException implements Exception {
  LicenseCollectionException(this.message);

  final String message;
}

/// Returns the license notices for [rootPackage], whose package directory is
/// [packageDir], built with the Dart SDK in [sdkDir].
///
/// Runs `dart pub deps --json` in [packageDir], so `dart pub get` must have
/// run there.
Future<String> collectLicenses({required String packageDir, required String sdkDir}) async {
  final ProcessResult deps = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: packageDir);
  if (deps.exitCode != 0) {
    throw LicenseCollectionException(
      '`dart pub deps --json` failed with exit code ${deps.exitCode}:\n${deps.stderr}',
    );
  }
  final List<String> dependencies = runtimeDependencies(
    jsonDecode(deps.stdout as String) as Map<String, Object?>,
  );

  final File packageConfig = findPackageConfig(packageDir);
  final Map<String, String> roots = packageRoots(
    jsonDecode(packageConfig.readAsStringSync()) as Map<String, Object?>,
    packageConfig.uri,
  );

  return formatNotices([
    (component: rootPackage, text: _readLicense(rootPackage, packageDir)),
    (component: sdkNoticeName, text: readSdkLicense(sdkDir)),
    for (final MapEntry(key: component, value: file) in dartRuntimeLicenseFiles.entries)
      (
        component: '$component (in the Dart runtime)',
        text: File(
          p.joinAll([packageDir, ...p.url.split(dartRuntimeLicensesDir), file]),
        ).readAsStringSync(),
      ),
    for (final String name in dependencies)
      (component: name, text: _readLicense(name, _rootOf(name, roots))),
  ]);
}

/// Returns the names, sorted, of the packages that [rootPackage] depends on
/// directly or transitively, leaving out its `dev_dependencies` and the
/// packages that only they bring in.
///
/// [depsJson] is the output of `dart pub deps --json`. That command can't
/// combine `--json` with `--no-dev`, so this follows each package's
/// `directDependencies`, which leave out dev dependencies.
List<String> runtimeDependencies(Map<String, Object?> depsJson) {
  final Map<String, List<String>> graph = {
    for (final Object? package in depsJson['packages']! as List<Object?>)
      if (package case {'name': final String name, 'directDependencies': final List<Object?> deps})
        name: deps.cast<String>(),
  };
  if (!graph.containsKey(rootPackage)) {
    throw LicenseCollectionException('`dart pub deps --json` does not list $rootPackage.');
  }
  final Set<String> seen = {rootPackage};
  final List<String> pending = [rootPackage];
  while (pending.isNotEmpty) {
    final String name = pending.removeLast();
    final List<String>? deps = graph[name];
    if (deps == null) {
      throw LicenseCollectionException('`dart pub deps --json` does not list $name.');
    }
    pending.addAll(deps.where(seen.add));
  }
  return (seen..remove(rootPackage)).toList()..sort();
}

/// Returns the `.dart_tool/package_config.json` file that applies to
/// [packageDir]: the one in [packageDir] or in the nearest directory above
/// it, such as a pub workspace root.
File findPackageConfig(String packageDir) {
  String dir = p.absolute(packageDir);
  while (true) {
    final file = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (file.existsSync()) {
      return file;
    }
    final String parent = p.dirname(dir);
    if (parent == dir) {
      throw LicenseCollectionException(
        'No .dart_tool/package_config.json in $packageDir or above it. Run `dart pub get`.',
      );
    }
    dir = parent;
  }
}

/// Returns each package's root directory, by package name, from the
/// [packageConfig] JSON that was read from [packageConfigUri].
///
/// Relative `rootUri` values resolve against [packageConfigUri], as the
/// package configuration format specifies.
Map<String, String> packageRoots(Map<String, Object?> packageConfig, Uri packageConfigUri) => {
  for (final Object? package in packageConfig['packages']! as List<Object?>)
    if (package case {'name': final String name, 'rootUri': final String rootUri})
      name: p.fromUri(packageConfigUri.resolve(rootUri)),
};

/// Returns the license text of the Dart SDK in [sdkDir].
///
/// Homebrew's Dart SDK keeps `LICENSE` in the directory above the SDK, so
/// that directory is checked when [sdkDir] has none.
String readSdkLicense(String sdkDir) {
  for (final String dir in [sdkDir, p.dirname(sdkDir)]) {
    final file = File(p.join(dir, 'LICENSE'));
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw LicenseCollectionException('No LICENSE file in the Dart SDK at $sdkDir or above it.');
}

/// Returns the license file in [dir], or `null` if it has none.
///
/// When several file names match, such as `LICENSE` and `LICENSE.md`, returns
/// the shortest, which is most likely the canonical one.
File? findLicenseFile(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    return null;
  }
  final List<File> matches = [
    for (final File file in directory.listSync().whereType<File>())
      if (_licenseFileName.hasMatch(p.basename(file.path))) file,
  ];
  if (matches.isEmpty) {
    return null;
  }
  return matches.reduce((a, b) => p.basename(a.path).length <= p.basename(b.path).length ? a : b);
}

/// Returns the notices as one document.
///
/// Components with the same license text share one copy of it, headed by
/// all of their names, in the order the components first appear in
/// [notices].
String formatNotices(List<LicenseNotice> notices) {
  final Map<String, List<String>> componentsByText = {};
  for (final notice in notices) {
    final String text = notice.text.replaceAll('\r\n', '\n').trimRight();
    componentsByText.putIfAbsent(text, () => []).add(notice.component);
  }
  final List<String> sections = [
    for (final MapEntry(key: text, value: components) in componentsByText.entries)
      '${_heading(components)}\n\n$text',
  ];
  return '${sections.join('\n\n${'-' * 80}\n\n')}\n';
}

String _heading(List<String> components) {
  if (components.length == 1) {
    return '${components.single} license:';
  }
  final String rest = components.sublist(0, components.length - 1).join(', ');
  return '$rest and ${components.last} license:';
}

String _rootOf(String name, Map<String, String> roots) =>
    roots[name] ??
    (throw LicenseCollectionException(
      '$name is not in .dart_tool/package_config.json. Run `dart pub get`.',
    ));

String _readLicense(String name, String dir) {
  final File? file = findLicenseFile(dir);
  if (file == null) {
    throw LicenseCollectionException(
      '$name has no license file in $dir, so it may not be legal to redistribute.',
    );
  }
  return file.readAsStringSync();
}
