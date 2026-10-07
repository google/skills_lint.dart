// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Writes and checks SHA-256 checksums in the format of `shasum -a 256`,
/// which `scripts/install.sh` reads.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'release_exception.dart';

/// The suffix of the checksum file that each build job writes next to its
/// archive.
const String checksumSuffix = '.sha256';

/// The name of the release asset that lists the checksum of every archive.
const String sha256SumsName = 'SHA256SUMS';

const String _archiveSuffix = '.tar.gz';

String _line(File file) => '${sha256.convert(file.readAsBytesSync())}  ${p.basename(file.path)}';

/// Writes `<file>.sha256`, which holds the line `<hash>  <name>` for [file],
/// and returns it.
File writeChecksum(File file) =>
    File('${file.path}$checksumSuffix')..writeAsStringSync('${_line(file)}\n');

/// Checks each `.sha256` file in [dir] against the file it names, then writes
/// their lines, sorted by file name, to [sha256SumsName] in [dir], deletes
/// the `.sha256` files and returns the [sha256SumsName] file.
///
/// Throws a [ReleaseException] if [dir] has no `.tar.gz` archive, an archive
/// has no `.sha256` file, or a `.sha256` file doesn't match its file.
File mergeChecksums(Directory dir) {
  final List<File> files = dir.listSync().whereType<File>().toList();
  final List<File> parts = [
    for (final file in files)
      if (file.path.endsWith(checksumSuffix)) file,
  ];
  final Set<String> archives = {
    for (final file in files)
      if (file.path.endsWith(_archiveSuffix)) p.basename(file.path),
  };
  if (archives.isEmpty) {
    throw ReleaseException('${dir.path} has no $_archiveSuffix archives.');
  }

  final Map<String, String> linesByName = {};
  for (final part in parts) {
    final String line = part.readAsStringSync().trim();
    final String name = line.split('  ').last;
    final file = File(p.join(dir.path, name));
    if (!file.existsSync()) {
      throw ReleaseException('${p.basename(part.path)} names $name, which is not in ${dir.path}.');
    }
    if (_line(file) != line) {
      throw ReleaseException('$name does not match its checksum in ${p.basename(part.path)}.');
    }
    linesByName[name] = line;
  }
  final List<String> unchecked = archives.difference(linesByName.keys.toSet()).toList()..sort();
  if (unchecked.isNotEmpty) {
    throw ReleaseException('No $checksumSuffix file for ${unchecked.join(', ')}.');
  }

  final List<String> names = linesByName.keys.toList()..sort();
  final sums = File(p.join(dir.path, sha256SumsName))
    ..writeAsStringSync(names.map((name) => '${linesByName[name]}\n').join());
  for (final part in parts) {
    part.deleteSync();
  }
  return sums;
}
