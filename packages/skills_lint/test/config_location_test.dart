// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/models/config_location.dart';
import 'package:test/test.dart';

void main() {
  final String cwd = p.normalize(p.absolute(Directory.current.path));

  group('formatConfigLocation', () {
    test('shows a file inside the working directory relative to it', () {
      final String file = p.join(cwd, 'nested', 'skills_lint.yaml');

      expect(
        formatConfigLocation((file: file, line: 3, column: 5)),
        '${p.join('nested', 'skills_lint.yaml')}:3:5',
      );
    });

    test('shows a file outside the working directory as an absolute path', () {
      final String file = p.join(p.dirname(cwd), 'elsewhere', 'skills_lint.yaml');

      expect(formatConfigLocation((file: file, line: 1, column: 1)), '$file:1:1');
    });
  });
}
