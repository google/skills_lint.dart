// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:tar/tar.dart';

import 'models/pub_archive.dart';

/// Runs [executable] with [arguments] in [workingDirectory].
///
/// [Process.run] fits this type. Tests pass a fake.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Lists the files `dart pub publish` would upload for the package that holds
/// a skill.
///
/// It asks pub to write the archive it would upload, then reads the archive's
/// file names. That way the result follows pub's own `.pubignore` and
/// `.gitignore` handling instead of a copy of it.
///
/// One loader serves one validation run. It builds each package's archive at
/// most once.
class PubArchiveLoader {
  PubArchiveLoader({ProcessRunner? runProcess}) : _runProcess = runProcess ?? Process.run;

  static const String _pubspecFileName = 'pubspec.yaml';
  static const String _dartExecutable = 'dart';
  static const String _publishToNone = 'none';
  static const String _archiveFileName = 'package.tar.gz';

  final ProcessRunner _runProcess;

  /// Archives by package root, so skills in one package share one pub run.
  final Map<String, Future<PubArchive>> _archivesByPackageRoot = {};

  /// The archive for the package that holds [skillDirectory].
  ///
  /// The package is the nearest directory at or above [skillDirectory] with a
  /// `pubspec.yaml`. Problems, such as no package or a failed pub run, come
  /// back as a [PubArchiveUnavailable] rather than an exception.
  /// [PubArchiveUnavailable.packageRoot] is set whenever a package was found.
  Future<PubArchive> archiveFor(Directory skillDirectory) async {
    final String? packageRoot = _findPackageRoot(
      Directory(p.normalize(skillDirectory.absolute.path)),
    );
    if (packageRoot == null) {
      return PubArchiveUnavailable(
        'No pubspec.yaml found at or above ${skillDirectory.path}, so there is no '
        'package for pub to publish. Disable pub-archive-includes-skill for this '
        'directory.',
      );
    }
    return _archivesByPackageRoot[packageRoot] ??= _buildArchive(packageRoot).then(
      (archive) => switch (archive) {
        PubArchiveUnavailable(:final String reason) => PubArchiveUnavailable(
          reason,
          packageRoot: packageRoot,
        ),
        PubArchiveFiles() => archive,
      },
    );
  }

  /// Forgets every archive built so far.
  ///
  /// Call this after the run writes files, such as `--fix`, because the
  /// archive may have changed.
  void clear() => _archivesByPackageRoot.clear();

  static String? _findPackageRoot(Directory start) {
    var current = start;
    while (true) {
      if (File(p.join(current.path, _pubspecFileName)).existsSync()) {
        return current.path;
      }
      final Directory parent = current.parent;
      if (parent.path == current.path) {
        return null;
      }
      current = parent;
    }
  }

  Future<PubArchive> _buildArchive(String packageRoot) async {
    final String pubspecPath = p.join(packageRoot, _pubspecFileName);
    final Pubspec pubspec;
    try {
      pubspec = Pubspec.parse(
        await File(pubspecPath).readAsString(),
        sourceUrl: Uri.file(pubspecPath),
      );
    } on Exception catch (e) {
      // Pubspec.parse throws ParsedYamlException from package:checked_yaml,
      // which is not a direct dependency, so match on Exception.
      return PubArchiveUnavailable('Could not read $pubspecPath: $e');
    }
    if (pubspec.publishTo == _publishToNone) {
      return PubArchiveUnavailable(
        '$pubspecPath sets publish_to: none, so pub never publishes this package. '
        'Disable pub-archive-includes-skill for this directory.',
      );
    }

    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'skills_lint_pub_archive',
    );
    try {
      final String archivePath = p.join(tempDirectory.path, _archiveFileName);
      final PubArchiveUnavailable? runFailure = await _writeArchive(
        packageRoot: packageRoot,
        archivePath: archivePath,
      );
      if (runFailure != null) {
        return runFailure;
      }
      return await _readArchive(packageRoot: packageRoot, archivePath: archivePath);
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  }

  /// Asks pub to write the archive for [packageRoot] to [archivePath].
  ///
  /// The result is `null` when pub succeeds.
  Future<PubArchiveUnavailable?> _writeArchive({
    required String packageRoot,
    required String archivePath,
  }) async {
    // --to-archive is hidden in `dart pub publish --help`. It writes the same
    // archive that publishing uploads. --skip-validation skips dependency
    // resolution and pub's validators, so this needs no network. If a later
    // pub drops the option, it exits with a usage error, and the rule reports
    // that instead of passing.
    final arguments = ['pub', 'publish', '--skip-validation', '--to-archive=$archivePath'];
    final command = '$_dartExecutable ${arguments.join(' ')}';
    final ProcessResult result;
    try {
      result = await _runProcess(_dartExecutable, arguments, workingDirectory: packageRoot);
    } on ProcessException catch (e) {
      return PubArchiveUnavailable(
        'Could not run `$command` in $packageRoot: ${e.message}. '
        'pub-archive-includes-skill needs the Dart SDK on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return PubArchiveUnavailable(
        '`$command` failed in $packageRoot with exit code ${result.exitCode}:\n'
                '${result.stderr}${result.stdout}'
            .trimRight(),
      );
    }
    return null;
  }

  static Future<PubArchive> _readArchive({
    required String packageRoot,
    required String archivePath,
  }) async {
    final files = <String>{};
    try {
      await TarReader.forEach(File(archivePath).openRead().transform(gzip.decoder), (
        TarEntry entry,
      ) {
        if (entry.type == TypeFlag.reg) {
          files.add(p.posix.normalize(entry.name));
        }
      });
    } on Exception catch (e) {
      // A missing file is a FileSystemException, a bad gzip stream a
      // FormatException and a bad tar header a TarException.
      return PubArchiveUnavailable('Could not read the archive pub wrote for $packageRoot: $e');
    }
    return PubArchiveFiles(packageRoot: packageRoot, files: files);
  }
}
