// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';

import 'package:skills_lint_release/src/archive.dart';
import 'package:skills_lint_release/src/homebrew_targets.dart';
import 'package:test/test.dart';

void main() {
  test('homebrewTargets keeps the macOS and Linux targets on arm64 and x64, in order', () {
    const List<ReleaseTarget> targets = [
      (name: 'linux-x64', abi: Abi.linuxX64, runner: 'ubuntu-latest'),
      (name: 'windows-x64', abi: Abi.windowsX64, runner: 'windows-latest'),
      (name: 'linux-riscv64', abi: Abi.linuxRiscv64, runner: 'ubuntu-latest'),
      (name: 'macos-arm64', abi: Abi.macosArm64, runner: 'macos-latest'),
    ];
    expect(homebrewTargets(targets).map((ReleaseTarget target) => target.name), [
      'linux-x64',
      'macos-arm64',
    ]);
  });
}
