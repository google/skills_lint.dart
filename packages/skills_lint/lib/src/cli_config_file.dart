// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'config_parser.dart';

/// The configuration file the command line reads, or `null` when
/// [ignoreConfig] is set (`--ignore-config`) or the file does not exist.
///
/// [configPath] is the `--config` value, or `null` for the default
/// `skills_lint.yaml`.
String? cliConfigFile({required bool ignoreConfig, String? configPath}) {
  if (ignoreConfig) {
    return null;
  }
  final String resolved = resolveConfigPath(configPath);
  return File(resolved).existsSync() ? resolved : null;
}
