// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/dart_directives.dart';
import 'src/source_conventions.dart';

void main() {
  late Directory root;
  late DartPackage package;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dart_directives_test.');
    package = DartPackage(name: 'pkg', srcRoot: p.join(root.path, 'lib', 'src'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Writes [content] to [relativePath] under [root] and returns its path.
  String write(String relativePath, String content) {
    final file = File(p.join(root.path, relativePath))..createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  String libPath(String relative) => p.join(root.path, 'lib', relative);

  group('filesImportedBy', () {
    test('ignores a path in a comment', () {
      write('test/a_test.dart', "// See 'package:pkg/src/a.dart'.\nvoid main() {}\n");
      expect(package.filesImportedBy(parseDirectories([p.join(root.path, 'test')])), isEmpty);
    });

    test('ignores a @docImport', () {
      write(
        'test/a_test.dart',
        "/// @docImport 'package:pkg/src/a.dart';\nlibrary;\n\nvoid main() {}\n",
      );
      expect(package.filesImportedBy(parseDirectories([p.join(root.path, 'test')])), isEmpty);
    });

    test('counts package and relative imports with either quote style', () {
      write(
        'test/a_test.dart',
        "import 'package:pkg/src/a.dart';\n"
            'import "package:pkg/src/b.dart";\n'
            "import '../lib/src/c.dart';\n"
            'export "../lib/src/nested/d.dart";\n',
      );
      expect(package.filesImportedBy(parseDirectories([p.join(root.path, 'test')])), {
        'a.dart',
        'b.dart',
        'c.dart',
        'nested/d.dart',
      });
    });

    test('drops dart:, other packages, and files outside lib/src', () {
      write(
        'test/a_test.dart',
        "import 'dart:io';\n"
            "import 'package:other/src/a.dart';\n"
            "import 'package:pkg/pkg.dart';\n"
            "import 'helper.dart';\n",
      );
      expect(package.filesImportedBy(parseDirectories([p.join(root.path, 'test')])), isEmpty);
    });
  });

  group('resolve', () {
    test('resolves a package URI to lib/', () {
      expect(package.resolve('package:pkg/src/a.dart', from: 'x.dart'), libPath('src/a.dart'));
    });

    test('resolves a relative URI from the containing file', () {
      final String from = libPath('src/nested/x.dart');
      expect(package.resolve('../a.dart', from: from), libPath('src/a.dart'));
    });

    test('returns null for other schemes and packages', () {
      expect(package.resolve('dart:io', from: 'x.dart'), isNull);
      expect(package.resolve('package:other/a.dart', from: 'x.dart'), isNull);
    });
  });

  group('exportedFiles', () {
    test('follows a re-export chain a -> b -> c', () {
      final String a = write('lib/pkg.dart', "export 'src/b.dart';\n");
      write('lib/src/b.dart', "export 'c.dart';\n");
      write('lib/src/c.dart', 'class C {}\n');
      expect(package.exportedFiles(a), {a, libPath('src/b.dart'), libPath('src/c.dart')});
    });

    test('counts exports with show and hide', () {
      final String a = write(
        'lib/pkg.dart',
        "export 'src/b.dart' show B;\nexport 'package:pkg/src/c.dart' hide C;\n",
      );
      write('lib/src/b.dart', 'class B {}\n');
      write('lib/src/c.dart', 'class C {}\n');
      expect(package.exportedFiles(a), containsAll([libPath('src/b.dart'), libPath('src/c.dart')]));
    });

    test('ignores imports', () {
      final String a = write('lib/pkg.dart', "import 'src/b.dart';\n");
      write('lib/src/b.dart', 'class B {}\n');
      expect(package.exportedFiles(a), {a});
    });

    test('includes an exported file outside lib/src, which srcRelative drops', () {
      final String a = write('lib/pkg.dart', "export 'other.dart';\n");
      final String other = write('lib/other.dart', 'class O {}\n');
      expect(package.exportedFiles(a), {a, other});
      expect(package.srcRelative(other), isNull);
    });
  });
}
