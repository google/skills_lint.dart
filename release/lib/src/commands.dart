// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The `release` command and its subcommands, which the steps of
/// `.github/workflows/release.yaml` run.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'archive.dart';
import 'checksums.dart';
import 'licenses.dart';
import 'paths.dart';
import 'release_exception.dart';
import 'release_info.dart';
import 'release_notes.dart';

/// Exit code for a command-line usage error, from BSD `sysexits.h`.
const int usageExitCode = 64;

/// Exit code for a release step that failed.
const int failureExitCode = 1;

/// Runs the `release` command with [arguments] and returns its exit code.
Future<int> runRelease(List<String> arguments) async {
  final runner = CommandRunner<void>('release', 'Builds and checks the skills_lint release assets.')
    ..addCommand(_PackageCommand())
    ..addCommand(_LicensesCommand())
    ..addCommand(_ChecksumsCommand())
    ..addCommand(_PrepareCommand());
  try {
    await runner.run(arguments);
    return 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return usageExitCode;
  } on ReleaseException catch (e) {
    stderr.writeln('release: error: ${e.message}');
    return failureExitCode;
  }
}

/// A `release` subcommand whose options are all mandatory.
abstract class _ReleaseCommand extends Command<void> {
  /// Returns the value of the mandatory option [name].
  ///
  /// Throws a [UsageException] if it wasn't given. `package:args` throws an
  /// [ArgumentError] instead when a mandatory option is read.
  String option(String name) {
    if (!argResults!.wasParsed(name)) {
      usageException('Option $name is mandatory.');
    }
    return argResults!.option(name)!;
  }

  /// Throws a [UsageException] if any positional arguments were given.
  void noRest() {
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
  }
}

class _PackageCommand extends _ReleaseCommand {
  _PackageCommand() {
    argParser
      ..addOption('target', mandatory: true, allowed: supportedTargets, help: 'The target.')
      ..addOption('output-dir', mandatory: true, help: 'The directory to write the archive to.');
  }

  @override
  String get name => 'package';

  @override
  String get description =>
      'Compiles the executable for this machine, packages it with its license notices, '
      'checks the archive and writes its .sha256 file.';

  @override
  Future<void> run() async {
    noRest();
    final File archive = await buildArchive(
      target: option('target'),
      outputDir: Directory(option('output-dir')),
    );
    stdout.writeln('Wrote ${archive.path} (${archive.lengthSync()} bytes).');
  }
}

class _LicensesCommand extends _ReleaseCommand {
  _LicensesCommand() {
    argParser.addOption('output', mandatory: true, help: 'The file to write the notices to.');
  }

  @override
  String get name => 'licenses';

  @override
  String get description => 'Writes the license notices for the executable.';

  @override
  Future<void> run() async {
    noRest();
    final String notices = await collectLicenses(
      packageDir: skillsLintPackageDir,
      sdkDir: dartSdkDir,
      runtimeLicensesDir: dartRuntimeLicensesDir,
    );
    File(option('output')).writeAsStringSync(notices);
  }
}

class _ChecksumsCommand extends _ReleaseCommand {
  @override
  String get name => 'checksums';

  @override
  String get invocation => 'release checksums <directory>';

  @override
  String get description =>
      'Checks each .sha256 file in <directory> and merges them into $sha256SumsName.';

  @override
  Future<void> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Give one directory.');
    }
    stdout.write(mergeChecksums(Directory(rest.single)).readAsStringSync());
  }
}

class _PrepareCommand extends _ReleaseCommand {
  _PrepareCommand() {
    argParser
      ..addOption('event', mandatory: true, help: 'The event that triggered the workflow.')
      ..addOption('ref-name', mandatory: true, help: 'The tag or branch of the workflow run.')
      ..addOption('run-id', mandatory: true, help: 'The ID of the workflow run.')
      ..addOption('notes-output', mandatory: true, help: 'The file to write release notes to.');
  }

  @override
  String get name => 'prepare';

  @override
  String get description =>
      'Checks the release tag against the pubspec.yaml version, prints the release as '
      r'NAME=value lines for $GITHUB_ENV and writes its notes from CHANGELOG.md.';

  @override
  Future<void> run() async {
    noRest();
    final String version = readPubspecVersion(
      File(p.join(skillsLintPackageDir, 'pubspec.yaml')).readAsStringSync(),
    );
    final ReleaseInfo info = resolveRelease(
      version: version,
      event: option('event'),
      refName: option('ref-name'),
      runId: option('run-id'),
    );
    final String section = changelogSection(
      File(p.join(skillsLintPackageDir, 'CHANGELOG.md')).readAsStringSync(),
      version,
    );
    File(option('notes-output')).writeAsStringSync(releaseNotes(section, dryRun: info.dryRun));
    stdout.write(environmentLines(info));
  }
}
