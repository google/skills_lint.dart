// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The `release` command and its subcommands, which the steps of
/// `.github/workflows/release_build_and_tag.yaml` run.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'archive.dart';
import 'checksums.dart';
import 'draft_release.dart';
import 'homebrew_formula.dart';
import 'homebrew_formula_check.dart';
import 'install_script.dart';
import 'licenses.dart';
import 'paths.dart';
import 'pub_dev_environment.dart';
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
    ..addCommand(_CheckPubDevEnvironmentCommand())
    ..addCommand(_VerifyDraftCommand())
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
        'release-version',
        help:
            'The version input of the run: the version to release. Omit it, or give an empty '
            'value as a dry run does, for a dry run.',
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
      releaseVersion: _nonEmpty(argResults!.option('release-version')),
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

class _CheckPubDevEnvironmentCommand extends _ReleaseCommand {
  _CheckPubDevEnvironmentCommand() {
    argParser
      ..addOption(
        'environment',
        mandatory: true,
        help: "A file with GitHub's JSON for the $pubDevEnvironment environment.",
      )
      ..addOption(
        'branch-policies',
        mandatory: true,
        help: "A file with GitHub's JSON for the environment's deployment branch policies.",
      );
  }

  @override
  String get name => 'check-pub-dev-environment';

  @override
  String get description =>
      'Fails unless the $pubDevEnvironment environment has a required reviewer and allows only '
      '$tagPrefix* tags.';

  @override
  void run() {
    noRest();
    checkPubDevEnvironment(
      environment: File(option('environment')).readAsStringSync(),
      branchPolicies: File(option('branch-policies')).readAsStringSync(),
    );
    stdout.writeln('The $pubDevEnvironment environment guards publishing.');
  }
}

class _VerifyDraftCommand extends _ReleaseCommand {
  _VerifyDraftCommand() {
    argParser
      ..addOption('ref-type', mandatory: true, help: 'The type of the ref of the run.')
      ..addOption('tag', mandatory: true, help: 'The tag of the run, which names the release.')
      ..addOption('repository', mandatory: true, help: 'The repository, as <owner>/<name>.')
      ..addOption('commit', mandatory: true, help: 'The commit that the tag points at.')
      ..addOption(
        'release-json',
        mandatory: true,
        help: 'A file with what `gh release view <tag> --json isDraft,isPrerelease` printed.',
      )
      ..addOption('assets', mandatory: true, help: 'A directory with every asset of the draft.')
      ..addOption('summary', mandatory: true, help: 'The file to add the job summary to.');
  }

  @override
  String get name => 'verify-draft';

  @override
  String get description =>
      'Checks that the draft release holds exactly the files the build of the commit made, that '
      'they match SHA256SUMS and that each has an attestation from that build, then prints '
      r'version and homebrew as name=value lines for $GITHUB_OUTPUT.';

  @override
  Future<void> run() async {
    noRest();
    final VerifiedDraft draft = await verifyDraft(
      refType: option('ref-type'),
      tag: option('tag'),
      repository: option('repository'),
      commit: option('commit'),
      releaseJson: File(option('release-json')).readAsStringSync(),
      assets: Directory(option('assets')),
    );
    File(option('summary')).writeAsStringSync(draft.summary, mode: FileMode.append);
    stdout.write(draft.outputLines);
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
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help:
            'Write nothing. Fail if the formula differs from what the template gives, or if its '
            'version breaks the release rules.',
      )
      ..addOption('version', help: 'Write the formula for this release. Needs --sha256sums.')
      ..addOption('sha256sums', help: "The release's $sha256SumsName file. Needs --version.")
      ..addOption('output', help: 'Write the formula here instead of Formula/skills_lint.rb.');
  }

  @override
  String get name => 'homebrew-formula';

  @override
  String get description =>
      'Writes Formula/skills_lint.rb from release/templates/skills_lint.rb.tmpl, with the version '
      'and checksums it has, or with those of the release that --version and --sha256sums give.';

  @override
  void run() {
    noRest();
    final formula = File(homebrewFormulaPath);
    // A Windows checkout can give these files CRLF line endings.
    final String template = File(homebrewTemplatePath).readAsStringSync().replaceAll('\r\n', '\n');
    final String current = formula.readAsStringSync().replaceAll('\r\n', '\n');
    if (argResults!.flag('check')) {
      if (['version', 'sha256sums', 'output'].any((name) => argResults!.option(name) != null)) {
        usageException('--check takes no other options.');
      }
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
    final String? version = argResults!.option('version');
    final String? sha256Sums = argResults!.option('sha256sums');
    if ((version == null) != (sha256Sums == null)) {
      usageException('Give both --version and --sha256sums, or neither.');
    }
    final output = File(argResults!.option('output') ?? homebrewFormulaPath);
    output.writeAsStringSync(
      version == null
          ? renderFormula(template, readFormula(current))
          : releaseFormula(
              template,
              version: version,
              sha256Sums: File(sha256Sums!).readAsStringSync(),
            ),
    );
    stdout.writeln('Wrote ${output.path}.');
  }
}

/// Returns [value], or null if it is null or empty. A workflow passes an
/// input that wasn't given as an empty value.
String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;

/// Returns the version in the skills_lint `pubspec.yaml`.
String _pubspecVersion() =>
    readPubspecVersion(File(p.join(skillsLintPackageDir, 'pubspec.yaml')).readAsStringSync());
