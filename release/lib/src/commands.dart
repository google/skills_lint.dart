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
import 'homebrew_formula.dart';
import 'install_script.dart';
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
    ..addCommand(_InstallScriptCommand())
    ..addCommand(_PrepareCommand())
    ..addCommand(_HomebrewMatrixCommand())
    ..addCommand(_HomebrewFormulaCommand());
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
      'Compiles the executable for this machine, checks that --version prints the pubspec.yaml '
      'version, packages it with its license notices, checks the archive and writes its .sha256 '
      'file.';

  @override
  Future<void> run() async {
    noRest();
    final File archive = await buildArchive(
      target: option('target'),
      version: _pubspecVersion(),
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

class _InstallScriptCommand extends _ReleaseCommand {
  _InstallScriptCommand() {
    argParser.addOption('output', mandatory: true, help: 'The file to write the script to.');
  }

  @override
  String get name => 'install-script';

  @override
  String get description =>
      'Writes scripts/install.sh with the pubspec.yaml version as the version it installs '
      'by default.';

  @override
  Future<void> run() async {
    noRest();
    final String script = File(
      p.join(skillsLintPackageDir, 'scripts', 'install.sh'),
    ).readAsStringSync();
    File(option('output')).writeAsStringSync(installScriptForVersion(script, _pubspecVersion()));
  }
}

class _PrepareCommand extends _ReleaseCommand {
  _PrepareCommand() {
    argParser
      ..addOption('event', mandatory: true, help: 'The event that started the workflow run.')
      ..addOption('ref-type', mandatory: true, help: 'The type of the ref of the run.')
      ..addOption('ref-name', mandatory: true, help: 'The branch or tag of the run.')
      ..addOption(
        'release',
        mandatory: true,
        allowed: ['true', 'false'],
        help: 'The release input of the run.',
      )
      ..addOption('notes-output', mandatory: true, help: 'The file to write release notes to.');
  }

  @override
  String get name => 'prepare';

  @override
  String get description =>
      'Works out what the workflow run does, prints it and the build matrix as name=value lines '
      r'for $GITHUB_OUTPUT and writes the release notes from CHANGELOG.md.';

  @override
  Future<void> run() async {
    noRest();
    final String version = _pubspecVersion();
    final ReleaseInfo info = resolveRelease(
      version: version,
      event: option('event'),
      refType: option('ref-type'),
      refName: option('ref-name'),
      release: option('release') == 'true',
    );
    final String section = changelogSection(
      File(p.join(skillsLintPackageDir, 'CHANGELOG.md')).readAsStringSync(),
      version,
    );
    File(option('notes-output')).writeAsStringSync('$section\n');
    stdout
      ..write(outputLines(info))
      ..writeln('matrix=${buildMatrix()}');
  }
}

class _HomebrewMatrixCommand extends _ReleaseCommand {
  @override
  String get name => 'homebrew-matrix';

  @override
  String get description =>
      'Prints the targets that the Homebrew formula installs, with the runner of each, as a '
      r'matrix=<json> line for $GITHUB_OUTPUT.';

  @override
  void run() {
    noRest();
    stdout.writeln('matrix=${buildMatrix(homebrewTargets())}');
  }
}

class _HomebrewFormulaCommand extends _ReleaseCommand {
  _HomebrewFormulaCommand() {
    argParser.addFlag(
      'check',
      negatable: false,
      help:
          'Write nothing. Fail if the formula differs from what the template gives, or if its '
          'version breaks the release rules.',
    );
  }

  @override
  String get name => 'homebrew-formula';

  @override
  String get description =>
      'Writes Formula/skills_lint.rb from release/templates/skills_lint.rb.tmpl, keeping its '
      'version and checksums.';

  @override
  void run() {
    noRest();
    final formula = File(homebrewFormulaPath);
    final String template = File(homebrewTemplatePath).readAsStringSync();
    final String current = formula.readAsStringSync();
    if (argResults!.flag('check')) {
      final List<String> problems = formulaProblems(
        current,
        template: template,
        pubspecVersion: _pubspecVersion(),
        changelog: File(p.join(skillsLintPackageDir, 'CHANGELOG.md')).readAsStringSync(),
      );
      if (problems.isNotEmpty) {
        throw ReleaseException(
          '${formula.path}:\n${problems.join('\n')}\n'
          'To regenerate it, run `dart run bin/release.dart homebrew-formula` in release/.',
        );
      }
      stdout.writeln('${formula.path} matches its template.');
      return;
    }
    formula.writeAsStringSync(renderFormula(template, readFormula(current)));
    stdout.writeln('Wrote ${formula.path}.');
  }
}

/// Returns the version in the skills_lint `pubspec.yaml`.
String _pubspecVersion() =>
    readPubspecVersion(File(p.join(skillsLintPackageDir, 'pubspec.yaml')).readAsStringSync());
