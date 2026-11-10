// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'config_location.dart';

/// A problem in a configuration, such as an unknown key.
@immutable
class ConfigProblem {
  const ConfigProblem(this.message, {this.location});

  /// What is wrong, without the location.
  final String message;

  /// Where the problem is.
  ///
  /// Is `null` for content that did not come from a file.
  final ConfigLocation? location;

  /// [message] prefixed with the formatted [location], as one line that
  /// stands on its own.
  String get text => switch (location) {
    null => message,
    final ConfigLocation location => '${formatConfigLocation(location)}: $message',
  };
}
