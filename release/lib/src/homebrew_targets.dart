// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The release targets that the Homebrew formula in `Formula/skills_lint.rb`
/// installs.
library;

import 'dart:ffi';

import 'archive.dart';

/// The ABIs that a Homebrew formula can select an archive for.
///
/// Homebrew runs on macOS and Linux, and a formula picks an archive with
/// `on_macos` or `on_linux` and `on_arm` or `on_intel`. It has no block for
/// any other architecture.
const Set<Abi> homebrewAbis = {Abi.macosArm64, Abi.macosX64, Abi.linuxArm64, Abi.linuxX64};

/// Returns the [targets] that Homebrew can install, in order.
List<ReleaseTarget> homebrewTargets([List<ReleaseTarget> targets = releaseTargets]) => [
  for (final ReleaseTarget target in targets)
    if (homebrewAbis.contains(target.abi)) target,
];
