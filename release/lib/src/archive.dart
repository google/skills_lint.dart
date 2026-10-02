// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Compiles the `skills_lint` executable for one target and packages it in
/// the archive that `scripts/install.sh` downloads.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'checksums.dart';
import 'licenses.dart';
import 'paths.dart';
import 'release_exception.dart';

/// The targets that each release has an archive for, named as
/// `scripts/install.sh` names them.
const List<String> supportedTargets = ['macos-arm64', 'macos-x64', 'linux-x64'];

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
String? hostTarget(Abi abi) => switch (abi) {
  Abi.macosArm64 => 'macos-arm64',
  Abi.macosX64 => 'macos-x64',
  Abi.linuxX64 => 'linux-x64',
  _ => null,
};

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

/// Builds the archive for [target] in [outputDir], with its `.sha256` file
/// next to it, and returns the archive.
///
/// Compiles the executable, runs it, writes the license notices next to it,
/// packages both, then checks the archive. Throws a [ReleaseException] if
/// [target] is not the host's target, since `dart compile exe` can't
/// cross-compile to it, or if a step fails.
Future<File> buildArchive({required String target, required Directory outputDir}) async {
  final String? host = hostTarget(Abi.current());
  if (target != host) {
    throw ReleaseException(
      'This machine builds ${host ?? 'no supported target'}, not $target. '
      'Supported targets: ${supportedTargets.join(', ')}.',
    );
  }
  final Directory stage = Directory.systemTemp.createTempSync('skills_lint_stage.');
  try {
    final String executable = p.join(stage.path, binaryName(target));
    await _run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      p.join('bin', 'skills_lint.dart'),
      '-o',
      executable,
    ], workingDirectory: skillsLintPackageDir);
    await smokeTest(executable);
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
  } finally {
    stage.deleteSync(recursive: true);
  }
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
