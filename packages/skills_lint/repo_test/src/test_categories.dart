// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The test directories, relative to the package root, with `/` separators.
///
/// CI runs each one as its own step: `dart test` for `test/` and
/// `dart test repo_test` for `repo_test/`. See "Where tests go" in
/// CONTRIBUTING.md.
library;

const List<String> testCategories = ['test', 'repo_test'];
