// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import 'models/source_region.dart';

/// The files that links in `SKILL.md` point to and that pub does not
/// publish, keyed by path relative to the package root, each with the region
/// of the first link to it.
final class UnpublishedLinks {
  /// Files outside the package, which pub never publishes.
  final outside = <String, SourceRegion>{};

  /// Files whose name in the archive differs in case, with that name.
  final wrongCase = <String, ({String actualFile, SourceRegion region})>{};

  /// Files inside the package that are not in the archive.
  final missing = <String, SourceRegion>{};
}

/// Sorts each of [links], an absolute path and the region of the link to
/// it, that pub does not publish by why: it is outside [packageRoot]
/// (`outside`), it is in [files] under different casing (`wrongCase`), or it
/// is missing from [files] (`missing`).
///
/// Each map is keyed by the path relative to [packageRoot], and holds the
/// region of the first link to that file.
UnpublishedLinks findUnpublishedLinks(
  Iterable<({String path, SourceRegion region})> links, {
  required String packageRoot,
  required Set<String> files,
}) {
  // Each archive file keyed by lowercase path, so a case mismatch on a
  // case-insensitive filesystem can be told apart from an ignored file.
  final Map<String, String> filesByLowerCase = {
    for (final String file in files) file.toLowerCase(): file,
  };
  final unpublished = UnpublishedLinks();
  for (final link in links) {
    final String archivePath = p.split(p.relative(link.path, from: packageRoot)).join('/');
    if (!p.isWithin(packageRoot, link.path)) {
      unpublished.outside.putIfAbsent(archivePath, () => link.region);
      continue;
    }
    if (files.contains(archivePath)) {
      continue;
    }
    if (filesByLowerCase[archivePath.toLowerCase()] case final String actualFile) {
      unpublished.wrongCase.putIfAbsent(
        archivePath,
        () => (actualFile: actualFile, region: link.region),
      );
    } else {
      unpublished.missing.putIfAbsent(archivePath, () => link.region);
    }
  }
  return unpublished;
}
