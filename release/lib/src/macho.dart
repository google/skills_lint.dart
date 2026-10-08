// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Reads the minimum macOS version from a macOS executable, so that a Dart
/// SDK that raises it fails the build instead of shipping silently.
library;

import 'dart:typed_data';

import 'release_exception.dart';

/// The minimum macOS version of the macOS executables.
///
/// It comes from the Dart SDK that compiles them: Dart 3.11 and later target
/// macOS 14. `RELEASING.md` lists the other places that state it.
const String macosMinimumVersion = '14.0';

const int _magic64 = 0xfeedfacf;
const int _headerSize = 32;
const int _lcVersionMinMacosx = 0x24;
const int _lcBuildVersion = 0x32;

/// Returns the minimum macOS version in the load commands of [binary], a
/// little-endian 64-bit Mach-O file, such as `14.0` or `10.13.4`.
///
/// Throws a [ReleaseException] if [binary] is not such a file or has no
/// `LC_BUILD_VERSION` or `LC_VERSION_MIN_MACOSX` command.
String macosMinimumOf(Uint8List binary) {
  final data = ByteData.sublistView(binary);
  if (binary.length < _headerSize || data.getUint32(0, Endian.little) != _magic64) {
    throw ReleaseException('The file is not a 64-bit Mach-O executable.');
  }
  final int commandCount = data.getUint32(16, Endian.little);
  int offset = _headerSize;
  for (var i = 0; i < commandCount && offset + 16 <= binary.length; i++) {
    final int command = data.getUint32(offset, Endian.little);
    switch (command) {
      case _lcBuildVersion:
        return _formatVersion(data.getUint32(offset + 12, Endian.little));
      case _lcVersionMinMacosx:
        return _formatVersion(data.getUint32(offset + 8, Endian.little));
    }
    offset += data.getUint32(offset + 4, Endian.little);
  }
  throw ReleaseException('The executable has no LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX.');
}

/// Throws a [ReleaseException] unless the minimum macOS version of [binary]
/// is [macosMinimumVersion].
void checkMacosMinimum(Uint8List binary) {
  final String minimum = macosMinimumOf(binary);
  if (minimum != macosMinimumVersion) {
    throw ReleaseException(
      'The executable needs macOS $minimum, but the release states macOS $macosMinimumVersion. '
      'The Dart SDK changed its minimum macOS version. Update macosMinimumVersion in '
      'release/lib/src/macho.dart and the places that RELEASING.md lists under Targets.',
    );
  }
}

/// Formats a version packed as `xxxx.yy.zz` in 32 bits.
String _formatVersion(int packed) {
  final int patch = packed & 0xff;
  final version = '${packed >> 16}.${(packed >> 8) & 0xff}';
  return patch == 0 ? version : '$version.$patch';
}
