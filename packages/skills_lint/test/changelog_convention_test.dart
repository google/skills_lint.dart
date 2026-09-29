// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

/// The longest bullet allowed in the top CHANGELOG section.
const int maxBulletLength = 300;

/// Checks the section under the first `## ` heading of CHANGELOG.md only.
/// Released sections are not rewritten, so they are not checked.
void main() {
  test('top CHANGELOG section bullets stay short', () {
    final List<String> lines = File('CHANGELOG.md').readAsLinesSync();
    final int start = lines.indexWhere((String l) => l.startsWith('## '));
    expect(start, isNot(-1), reason: 'CHANGELOG.md has no "## " version heading.');
    final String heading = lines[start].substring(3).trim();
    final List<String> long = [
      for (final String bullet in _bullets(lines.skip(start + 1)))
        if (bullet.length > maxBulletLength) bullet,
    ];
    expect(
      long,
      isEmpty,
      reason:
          'Shorten these bullets in the "$heading" section of CHANGELOG.md to at most '
          '$maxBulletLength characters, or split them into several bullets:\n'
          '${long.map(_preview).join('\n')}',
    );
  });
}

/// Returns the bullets before the next `## ` heading, joining wrapped lines.
List<String> _bullets(Iterable<String> lines) {
  final bullets = <String>[];
  for (final String line in lines.takeWhile((String l) => !l.startsWith('## '))) {
    if (line.startsWith('- ')) {
      bullets.add(line.substring(2).trim());
    } else if (line.trim().isNotEmpty && bullets.isNotEmpty) {
      bullets.last = '${bullets.last} ${line.trim()}';
    }
  }
  return bullets;
}

String _preview(String bullet) =>
    '- (${bullet.length} chars) "${bullet.length > 80 ? '${bullet.substring(0, 80)}...' : bullet}"';
