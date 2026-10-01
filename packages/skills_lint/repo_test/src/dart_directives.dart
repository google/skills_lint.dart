// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Reads `import` and `export` directives from Dart files and resolves them
/// to file paths.
///
/// Only directives in the syntax tree count. A URI in a comment or in a
/// `/// @docImport` is ignored, since neither runs the file it names.
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'models/source.dart';

/// A Dart package, identified by its name and its `lib/src` directory.
class DartPackage {
  /// Creates a package named [name] whose `lib/src` directory is [srcRoot].
  const DartPackage({required this.name, required this.srcRoot});

  /// The name used in `package:<name>/` URIs.
  final String name;

  /// The path of the package's `lib/src` directory.
  final String srcRoot;

  /// The path of the package's `lib` directory.
  String get libRoot => p.dirname(srcRoot);

  /// Returns the path that [uri] names when written in the file at [from].
  ///
  /// Returns null for URIs in other packages and for any other scheme, such
  /// as `dart:`.
  String? resolve(String uri, {required String from}) {
    final prefix = 'package:$name/';
    if (uri.startsWith(prefix)) {
      return p.normalize(p.join(libRoot, uri.substring(prefix.length)));
    }
    if (Uri.parse(uri).hasScheme) {
      return null;
    }
    return p.normalize(p.join(p.dirname(from), uri));
  }

  /// Returns the paths named by the `import` and `export` directives in
  /// [source], or only by its `export` directives if [exportsOnly] is true.
  /// URIs that [resolve] drops are left out.
  List<String> directiveTargets(Source source, {bool exportsOnly = false}) {
    final targets = <String>[];
    for (final NamespaceDirective directive
        in source.unit.directives.whereType<NamespaceDirective>()) {
      final String? uri = directive.uri.stringValue;
      if (uri == null || (exportsOnly && directive is! ExportDirective)) {
        continue;
      }
      final String? target = resolve(uri, from: source.path);
      if (target != null) {
        targets.add(target);
      }
    }
    return targets;
  }

  /// Returns [library] and every file reachable from it through `export`
  /// directives, following re-exports. Exports with `show` or `hide` count.
  Set<String> exportedFiles(String library) {
    final seen = <String>{};
    final List<String> pending = [p.normalize(library)];
    while (pending.isNotEmpty) {
      final String path = pending.removeLast();
      final file = File(path);
      if (seen.add(path) && file.existsSync()) {
        pending.addAll(directiveTargets(Source(path, file.readAsStringSync()), exportsOnly: true));
      }
    }
    return seen;
  }

  /// Returns the files below [srcRoot] named by an `import` or `export`
  /// directive in [sources], as [srcRelative] paths.
  Set<String> filesImportedBy(Iterable<Source> sources) {
    final imported = <String>{};
    for (final source in sources) {
      for (final String target in directiveTargets(source)) {
        final String? relative = srcRelative(target);
        if (relative != null) {
          imported.add(relative);
        }
      }
    }
    return imported;
  }

  /// Returns [path] relative to [srcRoot] with `/` separators, or null if
  /// [path] is not below [srcRoot].
  String? srcRelative(String path) {
    if (!p.isWithin(srcRoot, path)) {
      return null;
    }
    return p.posix.joinAll(p.split(p.relative(path, from: srcRoot)));
  }
}
