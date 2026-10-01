// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'convention_violation.dart';

/// A parsed Dart file and every node in its syntax tree.
class Source {
  Source(this.path, this.content) : _parsed = parseString(content: content, path: path);

  /// Wraps an inline [content] snippet for the detector tests.
  Source.snippet(String content, {String path = 'lib/snippet.dart'}) : this(path, content);

  /// Package-relative path with `/` separators.
  final String path;
  final String content;
  final ParseStringResult _parsed;

  /// Returns the root of the syntax tree.
  CompilationUnit get unit => _parsed.unit;

  /// Every node of the syntax tree, in source order.
  late final List<AstNode> nodes = (_NodeCollector()..visitNode(_parsed.unit)).nodes;

  /// Every comment in the file, in source order. Each `//` or `///` line is
  /// its own token.
  late final List<Token> comments = [
    for (Token? token = unit.beginToken; token != null; token = token.isEof ? null : token.next)
      for (Token? comment = token.precedingComments; comment != null; comment = comment.next)
        comment,
  ];

  ConventionViolation violationAt(int offset, String problem) =>
      ConventionViolation(path, _parsed.lineInfo.getLocation(offset).lineNumber, problem);
}

/// Collects every node of a syntax tree in source order.
class _NodeCollector extends GeneralizingAstVisitor<void> {
  final List<AstNode> nodes = [];

  @override
  void visitNode(AstNode node) {
    nodes.add(node);
    super.visitNode(node);
  }
}
