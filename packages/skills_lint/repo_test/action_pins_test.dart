// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/action_pins.dart';
import 'src/repo_paths.dart';
import 'src/source_conventions.dart';

/// Checks that the workflows in `.github/workflows/` pin each action,
/// reusable workflow and Docker image the same way.
///
/// `src/action_pins.dart` says why. `checkers/action_pins_test.dart` pins
/// what the detectors report on small snippets.
void main() {
  test('each action and reusable workflow has one pin across .github/workflows/', () {
    final List<ActionPin> pins = [
      for (final File file in _workflowFiles())
        ...findActionPins(
          p.posix.joinAll(p.split(p.relative(file.path, from: repoRoot))),
          file.readAsStringSync(),
        ),
    ];
    expect(
      pins,
      isNotEmpty,
      reason:
          'Found no `uses:` in ${_workflowDirectory.path}. The scan reads '
          'jobs.<id>.uses and jobs.<id>.steps[*].uses.',
    );
    expectNoViolations(findInconsistentPins(pins), fix: _fix);
  });
}

final Directory _workflowDirectory = Directory(p.join(repoRoot, '.github', 'workflows'));

/// The workflow files, sorted by path. GitHub reads both extensions.
List<File> _workflowFiles() =>
    _workflowDirectory
        .listSync()
        .whereType<File>()
        .where((file) => const {'.yaml', '.yml'}.contains(p.extension(file.path)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

const String _fix =
    'Pin every use of an action, reusable workflow or Docker image to the same '
    'ref and version comment in every file under .github/workflows/. When you '
    'update a pin by hand, update every use of it in the same change.';
