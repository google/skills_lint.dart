// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  group('Version drift guard', () {
    test('SarifDriver defaultDriverVersion matches pubspec.yaml version', () {
      final pubspecFile = File(p.normalize(p.absolute('pubspec.yaml')));
      expect(pubspecFile.existsSync(), isTrue, reason: 'pubspec.yaml must exist');

      final String content = pubspecFile.readAsStringSync();
      final pubspec = Pubspec.parse(content);

      expect(
        SarifDriver.defaultDriverVersion,
        equals(pubspec.version.toString()),
        reason: 'SarifDriver.defaultDriverVersion must stay in sync with pubspec.yaml version',
      );
    });
  });
}
