// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Compiles the `skills_lint` executable for one target and packages it in
/// the archive that `scripts/install.sh` downloads.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'checksums.dart';
import 'licenses.dart';
import 'macho.dart';
import 'paths.dart';
import 'release_exception.dart';

/// An operating system that a release can have an executable for, named as
/// in Dart's [Abi] and in the archive names.
enum TargetOs {
  macos(homebrewBlock: 'on_macos'),
  linux(homebrewBlock: 'on_linux'),
  windows(homebrewBlock: null);

  const TargetOs({required this.homebrewBlock});

  /// The Homebrew formula block that selects this system, or null if
  /// Homebrew doesn't run on it.
  final String? homebrewBlock;
}

/// A CPU architecture that a release can have an executable for, named as
/// in Dart's [Abi] and in the archive names.
enum TargetArch {
  arm64(homebrewBlock: 'on_arm'),
  x64(homebrewBlock: 'on_intel'),
  riscv64(homebrewBlock: null);

  const TargetArch({required this.homebrewBlock});

  /// The Homebrew formula block that selects this architecture, or null if
  /// a formula can't select it.
  final String? homebrewBlock;
}

/// A platform that each release has an archive for, and the GitHub-hosted
/// runner image that builds it.
final class ReleaseTarget {
  const ReleaseTarget({required this.os, required this.arch, required this.runner});

  final TargetOs os;

  final TargetArch arch;

  /// The runner image that builds this target's executable. `dart compile
  /// exe` builds for the host only, so it runs on this target's platform.
  final String runner;

  /// The platform in the archive's name, such as `macos-arm64`.
  String get name => '${os.name}-${arch.name}';

  /// The ABI that runs the executable.
  // Abi.toString() is documented as `<os>_<arch>`, the names TargetOs and
  // TargetArch use.
  Abi get abi => Abi.values.singleWhere((Abi abi) => '$abi' == '${os.name}_${arch.name}');
}

/// The targets that each release has an archive for.
///
/// The build matrix of the release workflow comes from [buildMatrix], and
/// `scripts/install.sh` reads the targets from a release's `SHA256SUMS`.
const List<ReleaseTarget> releaseTargets = [
  ReleaseTarget(os: TargetOs.macos, arch: TargetArch.arm64, runner: 'macos-latest'),
  // GitHub has no standard `macos-latest` label for Intel, so this names the
  // newest standard Intel macOS image.
  ReleaseTarget(os: TargetOs.macos, arch: TargetArch.x64, runner: 'macos-26-intel'),
  ReleaseTarget(os: TargetOs.linux, arch: TargetArch.x64, runner: 'ubuntu-latest'),
  // GitHub has no `ubuntu-latest` label for arm64, so this names the arm64
  // image of the Ubuntu version that `ubuntu-latest` runs.
  ReleaseTarget(os: TargetOs.linux, arch: TargetArch.arm64, runner: 'ubuntu-24.04-arm'),
];

/// The names of [releaseTargets].
final List<String> supportedTargets = [
  for (final ReleaseTarget target in releaseTargets) target.name,
];

const String _licenseName = 'LICENSE';

/// The name of the executable for [target], at the top level of its archive.
String binaryName(String target) => 'skills_lint-$target';

/// The name of the archive for [target].
String archiveName(String target) => 'skills_lint-$target.tar.gz';

/// Returns the target that runs on [abi], or `null` if no archive is built
/// for it.
///
/// `dart compile exe` builds for the host only, so this is the only target
/// that a machine can build.
String? hostTarget(Abi abi) => releaseTargets
    .where((ReleaseTarget target) => target.abi == abi)
    .map((ReleaseTarget target) => target.name)
    .firstOrNull;

/// The targets of [targets] that the Homebrew formula installs: those whose
/// system and architecture each have a formula block.
List<ReleaseTarget> homebrewTargets([List<ReleaseTarget> targets = releaseTargets]) => [
  for (final ReleaseTarget target in targets)
    if (target.os.homebrewBlock != null && target.arch.homebrewBlock != null) target,
];

/// Returns a GitHub Actions `strategy.matrix` as JSON: an `include` entry for
/// each of [targets], with the `target` and the runner (`os`) that builds it.
///
/// The release workflow's `build` job uses it for all of [releaseTargets].
String buildMatrix([List<ReleaseTarget> targets = releaseTargets]) => jsonEncode({
  'include': [
    for (final ReleaseTarget target in targets) {'os': target.runner, 'target': target.name},
  ],
});

/// Writes the archive for [target] to [outputDir] and returns it. The archive
/// holds the executable and `LICENSE` from [stage], at its top level.
///
/// Throws a [ReleaseException] if either file is missing or `tar` fails.
Future<File> writeArchive({
  required Directory stage,
  required String target,
  required Directory outputDir,
}) async {
  final List<String> members = [binaryName(target), _licenseName];
  for (final name in members) {
    if (!File(p.join(stage.path, name)).existsSync()) {
      throw ReleaseException('${stage.path} has no $name to package.');
    }
  }
  final archive = File(p.join(outputDir.path, archiveName(target)));
  await _run(
    'tar',
    ['-czf', archive.path, '-C', stage.path, ...members],
    // Keeps macOS tar from adding ._ files for extended attributes.
    environment: {'COPYFILE_DISABLE': '1'},
  );
  return archive;
}

/// Unpacks [archive] to a temporary directory and checks that it holds only
/// the executable for [target] and `LICENSE`, and that `--help` runs.
///
/// Throws a [ReleaseException] if a check fails.
Future<void> verifyArchive(File archive, String target) async {
  final Directory temp = Directory.systemTemp.createTempSync('skills_lint_release.');
  try {
    await _run('tar', ['-xzf', archive.path, '-C', temp.path]);
    final List<String> contents = [
      for (final FileSystemEntity entity in temp.listSync(recursive: true))
        if (entity is! Directory) p.relative(entity.path, from: temp.path),
    ]..sort();
    final List<String> expected = [_licenseName, binaryName(target)]..sort();
    if (contents.join('\n') != expected.join('\n')) {
      throw ReleaseException(
        '${p.basename(archive.path)} holds ${contents.join(', ')}; '
        'expected ${expected.join(', ')}.',
      );
    }
    await smokeTest(p.join(temp.path, binaryName(target)));
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// Runs the [executable] with `--help`.
///
/// Throws a [ReleaseException] if it exits with a nonzero code.
Future<void> smokeTest(String executable) => _run(executable, ['--help']);

/// Runs the [executable] with `--version`.
///
/// Throws a [ReleaseException] if it exits with a nonzero code or prints
/// anything but [version].
Future<void> checkVersion(String executable, String version) async {
  final ProcessResult result = await Process.run(executable, ['--version']);
  final String printed = (result.stdout as String).trim();
  if (result.exitCode != 0 || printed != version) {
    throw ReleaseException(
      '`${p.basename(executable)} --version` printed "$printed" and exited with code '
      '${result.exitCode}; expected $version, the pubspec.yaml version.',
    );
  }
}

/// Builds the archive for [target] in [outputDir], with its `.sha256` file
/// next to it, and returns the archive.
///
/// Compiles the executable, then calls [packageExecutable] with [version].
/// Throws a [ReleaseException] if [target] is not the host's target, since
/// `dart compile exe` can't cross-compile to it, or if a step fails.
Future<File> buildArchive({
  required String target,
  required String version,
  required Directory outputDir,
}) async {
  final String? host = hostTarget(Abi.current());
  if (target != host) {
    throw ReleaseException(
      'This machine builds ${host ?? 'no supported target'}, not $target. '
      'Supported targets: ${supportedTargets.join(', ')}.',
    );
  }
  final Directory stage = Directory.systemTemp.createTempSync('skills_lint_stage.');
  try {
    await _run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      p.join('bin', 'skills_lint.dart'),
      '-o',
      p.join(stage.path, binaryName(target)),
    ], workingDirectory: skillsLintPackageDir);
    return await packageExecutable(
      stage: stage,
      target: target,
      version: version,
      outputDir: outputDir,
    );
  } finally {
    stage.deleteSync(recursive: true);
  }
}

/// Packages the executable for [target] in [stage] as the archive for
/// [target] in [outputDir], with its `.sha256` file next to it, and returns
/// the archive.
///
/// Checks the minimum macOS version of a macOS executable, runs the
/// executable, checks that it prints [version] for `--version`, writes the
/// license notices to `LICENSE` in [stage], packages both, then checks the
/// archive. Throws a [ReleaseException] if a step fails.
Future<File> packageExecutable({
  required Directory stage,
  required String target,
  required String version,
  required Directory outputDir,
}) async {
  final String executable = p.join(stage.path, binaryName(target));
  if (target.startsWith('macos-')) {
    checkMacosMinimum(File(executable).readAsBytesSync());
  }
  await smokeTest(executable);
  await checkVersion(executable, version);
  File(p.join(stage.path, _licenseName)).writeAsStringSync(
    await collectLicenses(
      packageDir: skillsLintPackageDir,
      sdkDir: dartSdkDir,
      runtimeLicensesDir: dartRuntimeLicensesDir,
    ),
  );
  outputDir.createSync(recursive: true);
  final File archive = await writeArchive(stage: stage, target: target, outputDir: outputDir);
  await verifyArchive(archive, target);
  writeChecksum(archive);
  return archive;
}

/// Runs [executable], passing its output through, and throws a
/// [ReleaseException] if it exits with a nonzero code.
Future<void> _run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  final int exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ReleaseException(
      '`${[p.basename(executable), ...arguments].join(' ')}` failed with exit code $exitCode.',
    );
  }
}
