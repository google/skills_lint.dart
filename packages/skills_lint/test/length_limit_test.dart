// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/src/length_limit.dart';
import 'package:test/test.dart';

void main() {
  group('LengthLimit', () {
    test('without a specification maximum is not configured', () {
      const limit = LengthLimit(maxLength: 500);

      expect(limit.isConfigured, isFalse);
      expect(limit.isBelowSpec, isFalse);
      expect(limit.isAboveSpec, isFalse);
    });

    test('equal to the specification maximum is not configured', () {
      const limit = LengthLimit(maxLength: 1024, specMaxLength: 1024);

      expect(limit.isConfigured, isFalse);
      expect(limit.isBelowSpec, isFalse);
      expect(limit.isAboveSpec, isFalse);
    });

    test('below the specification maximum is configured and below spec', () {
      const limit = LengthLimit(maxLength: 1023, specMaxLength: 1024);

      expect(limit.isConfigured, isTrue);
      expect(limit.isBelowSpec, isTrue);
      expect(limit.isAboveSpec, isFalse);
    });

    test('above the specification maximum is configured and above spec', () {
      const limit = LengthLimit(maxLength: 1025, specMaxLength: 1024);

      expect(limit.isConfigured, isTrue);
      expect(limit.isBelowSpec, isFalse);
      expect(limit.isAboveSpec, isTrue);
    });
  });
}
