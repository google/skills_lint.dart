// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/action_pins.dart';
import 'src/repo_paths.dart';
import 'src/source_conventions.dart';

/// Checks that each action, reusable workflow and Docker image has one pin.
///
/// Covers the workflows in `.github/workflows/` and the composite actions in
/// `.github/actions/`.
///
/// `src/action_pins.dart` says why. `checkers/action_pins_test.dart` pins
/// what the detectors report on small snippets.
void main() {
  test('each action and reusable workflow has one pin across workflows and actions', () {
    final List<ActionPin> pins = [
      for (final File file in actionPinFiles(repoRoot))
        ...findActionPins(
          p.posix.joinAll(p.split(p.relative(file.path, from: repoRoot))),
          file.readAsStringSync(),
        ),
    ];
    expect(
      pins,
      isNotEmpty,
      reason:
          'Found no `uses:` under ${p.join(repoRoot, '.github')}. The scan reads '
          'jobs.<id>.uses, jobs.<id>.steps[*].uses and runs.steps[*].uses.',
    );
    expectNoViolations(findInconsistentPins(pins), fix: _fix);
  });
}

const String _fix =
    'Pin every use of an action, reusable workflow or Docker image to the same '
    'ref and version comment in every file under .github/workflows/ and '
    '.github/actions/. '
    'To update an action, have Dependabot do it rather than editing pins by '
    'hand: on GitHub, open Insights > Dependency graph > Dependabot, click '
    '"Last checked <time> ago" next to a github-actions manifest, then click '
    '"Check for updates". Dependabot opens one pull request that updates '
    'every use of each action, for versions released at least 7 days ago '
    '(the cooldown in .github/dependabot.yaml).';
