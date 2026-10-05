// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:skills_lint_release/src/macho.dart';
import 'package:skills_lint_release/src/paths.dart';
import 'package:skills_lint_release/src/release_exception.dart';
import 'package:test/test.dart';

const int _lcSegment64 = 0x19;
const int _lcBuildVersion = 0x32;
const int _lcVersionMinMacosx = 0x24;

/// Encodes [major].[minor].[patch] as Mach-O packs it: `xxxx.yy.zz`.
int _version(int major, int minor, [int patch = 0]) => major << 16 | minor << 8 | patch;

/// Returns a little-endian 64-bit Mach-O header followed by [commands], each
/// a list of 32-bit words that starts with the command and its size.
Uint8List _machO(List<List<int>> commands, {int magic = 0xfeedfacf}) {
  final List<int> words = [
    magic, 0x0100000c, 0, 2, commands.length, //
    commands.fold(0, (size, c) => size + c.length * 4), 0, 0,
    for (final command in commands) ...command,
  ];
  final data = ByteData(words.length * 4);
  for (var i = 0; i < words.length; i++) {
    data.setUint32(i * 4, words[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> _buildVersion(int minos) => [_lcBuildVersion, 24, 1, minos, _version(14, 4), 0];

void main() {
  group('macosMinimumOf', () {
    test('reads minos from LC_BUILD_VERSION', () {
      final Uint8List binary = _machO([
        [_lcSegment64, 16, 0, 0],
        _buildVersion(_version(14, 0)),
      ]);
      expect(macosMinimumOf(binary), '14.0');
    });

    test('includes a patch version that is not zero', () {
      expect(macosMinimumOf(_machO([_buildVersion(_version(10, 13, 4))])), '10.13.4');
    });

    test('reads LC_VERSION_MIN_MACOSX, which older SDKs write', () {
      final Uint8List binary = _machO([
        [_lcVersionMinMacosx, 16, _version(10, 13), _version(11, 1)],
      ]);
      expect(macosMinimumOf(binary), '10.13');
    });

    test('throws for a file that is not a 64-bit Mach-O executable', () {
      expect(
        () => macosMinimumOf(_machO([_buildVersion(_version(14, 0))], magic: 0xcafebabe)),
        throwsA(isA<ReleaseException>()),
      );
      expect(() => macosMinimumOf(Uint8List(4)), throwsA(isA<ReleaseException>()));
    });

    test('throws when no load command names a minimum version', () {
      expect(
        () => macosMinimumOf(
          _machO([
            [_lcSegment64, 16, 0, 0],
          ]),
        ),
        throwsA(
          isA<ReleaseException>().having((e) => e.message, 'message', contains('LC_BUILD_VERSION')),
        ),
      );
    });
  });

  group('checkMacosMinimum', () {
    test('passes for the expected minimum', () {
      checkMacosMinimum(_machO([_buildVersion(_version(14, 0))]));
    });

    test('fails for another minimum and says what to update', () {
      expect(
        () => checkMacosMinimum(_machO([_buildVersion(_version(15, 0))])),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            allOf(contains('15.0'), contains(macosMinimumVersion), contains('install.sh')),
          ),
        ),
      );
    });
  });

  test('install.sh checks for the same macOS version', () {
    final String script = File(
      p.join(skillsLintPackageDir, 'scripts', 'install.sh'),
    ).readAsStringSync();
    expect(script, contains('\nMIN_MACOS_VERSION=${macosMinimumVersion.split('.').first}\n'));
  });
}
