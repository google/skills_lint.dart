// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../models/skills_ignores.dart';
import '../reporters/reporter.dart';
import 'skills_ignores_storage.dart';
import 'write_boundary.dart';

final _log = Logger('skills_lint');

/// Default filename for the per-run ignore baseline file.
///
/// Referenced both by production code (the `--generate-baseline` help text in
/// the CLI) and by tests, so this is intentionally not `@visibleForTesting`.
const defaultIgnoreFileName = 'skills_lint_ignore.json';

/// An ignore file path paired with its [WriteBoundary] and how missing files
/// behave.
@immutable
sealed class IgnoreFileTarget {
  const IgnoreFileTarget._({required this.path, required this.boundary});

  /// The default `skills_lint_ignore.json` inside [directory], confined to
  /// [targetBoundary].
  ///
  /// When absent on disk, validation loads empty ignores without creating the
  /// file.
  factory IgnoreFileTarget.defaultIn(Directory directory, {required WriteBoundary targetBoundary}) =
      _DefaultIgnoreFileTarget;

  /// An ignore file named in a configuration file, confined to
  /// [configDirectory] (plus [allowWrite]) when the configuration came from a
  /// file.
  ///
  /// When absent on disk, validation initializes an empty baseline file if
  /// [boundary] permits it.
  factory IgnoreFileTarget.fromConfiguration(
    String path, {
    required String? configDirectory,
    required List<String> allowWrite,
  }) = _ExplicitIgnoreFileTarget.fromConfiguration;

  /// An ignore file passed on the command line (`--ignore-file`) or through
  /// the API, which has no [WriteBoundary].
  ///
  /// When absent on disk, validation initializes an empty baseline file.
  const factory IgnoreFileTarget.fromOverride(String path) = _ExplicitIgnoreFileTarget.fromOverride;

  /// The absolute path to the ignore file.
  final String path;

  /// The boundary that creating or saving [path] must stay inside.
  final WriteBoundary boundary;

  /// Whether validation initializes an empty file on disk when [path] does not
  /// exist yet.
  bool get createWhenMissing;

  /// The target for [skillDir] after a skill rename.
  IgnoreFileTarget afterSkillRename(Directory skillDir);
}

final class _DefaultIgnoreFileTarget extends IgnoreFileTarget {
  _DefaultIgnoreFileTarget(Directory directory, {required WriteBoundary targetBoundary})
    : super._(path: p.join(directory.path, defaultIgnoreFileName), boundary: targetBoundary);

  @override
  bool get createWhenMissing => false;

  @override
  IgnoreFileTarget afterSkillRename(Directory skillDir) =>
      _DefaultIgnoreFileTarget(skillDir, targetBoundary: boundary);
}

final class _ExplicitIgnoreFileTarget extends IgnoreFileTarget {
  _ExplicitIgnoreFileTarget.fromConfiguration(
    String path, {
    required String? configDirectory,
    required List<String> allowWrite,
  }) : super._(
         path: path,
         boundary: configDirectory == null
             ? const WriteBoundary.none()
             : WriteBoundary(configDirectory, allowed: allowWrite),
       );

  const _ExplicitIgnoreFileTarget.fromOverride(String path)
    : super._(path: path, boundary: const WriteBoundary.none());

  @override
  bool get createWhenMissing => true;

  @override
  IgnoreFileTarget afterSkillRename(Directory skillDir) => this;
}

/// Loads and saves ignore files for one validation session, enforcing each
/// target's [WriteBoundary] before creating or replacing a file.
class IgnoreFileWriter {
  IgnoreFileWriter(this._reporter);

  final Reporter _reporter;
  final SkillsIgnoresStorage _storage = SkillsIgnoresStorage();

  /// Every [WriteBoundary] recorded for each ignore file path.
  ///
  /// Multiple scan targets can share an ignore file, so writing to that path
  /// must stay inside all of their boundaries.
  final Map<String, List<WriteBoundary>> _boundariesByPath = {};

  /// Ignore file paths created during [load] in this session, so a narrower
  /// boundary recorded later can remove and refuse a file that escaped it.
  final Set<String> _createdInSession = {};

  /// Malformed entries found the first time each ignore file was loaded, so
  /// [saveBaseline] can report what is dropped before replacing the file.
  final Map<String, List<IgnoreProblem>> _problemsByPath = {};

  /// Ignore file paths whose dropped entries [saveBaseline] has already
  /// reported.
  final Set<String> _reportedDroppedPaths = {};

  bool _writeRefused = false;

  /// Whether creating or saving an ignore file was refused because the path
  /// fell outside its [WriteBoundary].
  bool get writeRefused => _writeRefused;

  /// Records [target]'s boundary, loads [SkillsIgnores] if the file exists, or
  /// initializes an empty file on disk when [IgnoreFileTarget.createWhenMissing]
  /// is true.
  ///
  /// Reports malformed entries the first time a file is loaded.
  Future<SkillsIgnores> load(IgnoreFileTarget target) async {
    recordBoundary(target);
    final file = File(target.path);

    if (file.existsSync()) {
      final IgnoresLoad loaded = await _storage.load(target.path);
      // TODO(reidbaker-agent): https://github.com/google/skills_lint.dart/issues/183
      // Make an ignore file with errors fail the run in 0.6.0.
      if (loaded.problems.isNotEmpty && !_problemsByPath.containsKey(target.path)) {
        _problemsByPath[target.path] = loaded.problems;
        for (final IgnoreProblem problem in loaded.problems) {
          _reporter.onIgnoreFileError(problem.message);
        }
      }
      return loaded.ignores;
    }

    if (target.createWhenMissing && !_refuseWrite(target.path)) {
      _log.warning('File not found generating-baseline');
      try {
        await _storage.save(target.path, SkillsIgnores(skills: {}));
        _createdInSession.add(target.path);
      } on FileSystemException {
        // Ignore write errors and return empty ignores.
      }
    }

    return SkillsIgnores(skills: {});
  }

  /// Records [target]'s boundary against its path without reading the file.
  ///
  /// If an earlier target in the same session initialized a missing file at
  /// [target]'s path and the newly added boundary refuses it, deletes that
  /// initialized file and records the refusal.
  void recordBoundary(IgnoreFileTarget target) {
    (_boundariesByPath[target.path] ??= []).add(target.boundary);
    if (_createdInSession.contains(target.path)) {
      final String? reason = target.boundary.refusal(target.path);
      if (reason != null) {
        _createdInSession.remove(target.path);
        try {
          File(target.path).deleteSync();
        } on FileSystemException {
          // Best-effort cleanup of the file created earlier in this session.
        }
        _reporter.onWriteRefused(action: "write ignore file '${target.path}'", reason: reason);
        _writeRefused = true;
      }
    }
  }

  /// Moves recorded load problems from [oldIgnorePath] to [newTarget] and
  /// records [newTarget]'s boundary after `--fix` renames a skill directory.
  void moveRenamedIgnoreFile({required String oldIgnorePath, required IgnoreFileTarget newTarget}) {
    recordBoundary(newTarget);
    final List<IgnoreProblem>? problems = _problemsByPath.remove(oldIgnorePath);
    if (problems != null) {
      _problemsByPath[newTarget.path] = problems;
    }
  }

  /// Saves [ignores] to [ignoreFilePath] when every boundary recorded for it
  /// permits the write.
  ///
  /// Before replacing a file that had unreadable entries on [load], reports
  /// that those entries are not carried over.
  Future<void> saveBaseline(String ignoreFilePath, SkillsIgnores ignores) async {
    final List<IgnoreProblem>? problems = _problemsByPath[ignoreFilePath];
    if (problems != null && _reportedDroppedPaths.add(ignoreFilePath)) {
      _reporter.onIgnoreEntriesDropped(
        ignoreFilePath,
        entryCount: problems.length,
        skills: {for (final IgnoreProblem(:skill) in problems) ?skill}.toList()..sort(),
      );
    }
    if (_refuseWrite(ignoreFilePath)) {
      return;
    }
    try {
      await _storage.save(ignoreFilePath, ignores);
    } on FileSystemException catch (e) {
      _reporter.onBaselineFailed(ignoreFilePath, e);
    }
  }

  bool _refuseWrite(String ignoreFilePath) {
    for (final WriteBoundary boundary in _boundariesByPath[ignoreFilePath] ?? const []) {
      final String? reason = boundary.refusal(ignoreFilePath);
      if (reason != null) {
        _reporter.onWriteRefused(action: "write ignore file '$ignoreFilePath'", reason: reason);
        _writeRefused = true;
        return true;
      }
    }
    return false;
  }
}
