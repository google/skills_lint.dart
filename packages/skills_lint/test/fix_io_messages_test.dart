// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:skills_lint/src/reporters/fix_io_messages.dart';
import 'package:test/test.dart';

void main() {
  group('FixIoMessages.describe', () {
    test('prefers the OS error message', () {
      expect(
        FixIoMessages.describe(
          const FileSystemException('Cannot open file', '/a', OSError('Permission denied', 13)),
        ),
        'Permission denied',
      );
    });

    test('falls back to the exception message without an OS error', () {
      expect(FixIoMessages.describe(const FileSystemException('Rename failed')), 'Rename failed');
    });

    test('falls back to the text of the exception when both messages are empty', () {
      expect(
        FixIoMessages.describe(const FileSystemException('', '/a', OSError())),
        contains('FileSystemException'),
      );
    });

    test('falls back to the text of any other error', () {
      expect(FixIoMessages.describe(StateError('boom')), 'Bad state: boom');
    });
  });
}
