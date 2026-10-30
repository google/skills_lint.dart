// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/readme_anchors.dart';

void main() {
  test('headingAnchors matches the ids pub.dev renders for README headings', () {
    // Expected ids copied from https://pub.dev/packages/skills_lint. If this
    // fails, headingAnchors no longer renders headings the way pub.dev does.
    const markdown =
        '### 1. Dart developers — pub.dev\n'
        '#### As a project dev_dependency\n'
        '### 2. `install.sh` — Linux + macOS, no Dart required\n'
        '### Recipe: Dart-native pre-commit hook\n';
    expect(headingAnchors(markdown), [
      '1-dart-developers--pubdev',
      'as-a-project-dev_dependency',
      '2-installsh--linux--macos-no-dart-required',
      'recipe-dart-native-pre-commit-hook',
    ]);
  });
}
