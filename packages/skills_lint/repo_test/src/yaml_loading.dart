// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A detector for code that parses YAML with `package:yaml` or `Pubspec.parse`
/// directly instead of through `YamlLimits` in `lib/src/yaml_limits.dart`.
///
/// `package:yaml` shares the node behind each alias, so a few hundred bytes
/// can describe billions of values, and it hashes collection mapping keys in
/// time exponential in their nesting. Code that walks, prints or compares
/// such a value from unbounded input exhausts memory or CPU. `YamlLimits`
/// rejects those documents before any caller sees the value, so a parse that
/// skips it reopens that hole for whatever input reaches it.
///
/// Change this rule if `package:yaml` bounds alias expansion and key hashing
/// itself, or if skills_lint stops reading YAML it does not control.
library;

import 'package:analyzer/dart/ast/ast.dart';

import 'models/convention_violation.dart';
import 'models/source.dart';

/// The top-level `package:yaml` functions that parse a YAML string.
const Set<String> _yamlLoaderNames = {
  'loadYaml',
  'loadYamlNode',
  'loadYamlDocument',
  'loadYamlDocuments',
  'loadYamlStream',
};

/// Reports each call or tear-off in [source] of `loadYaml`, `loadYamlNode`,
/// `loadYamlDocument`, `loadYamlDocuments` or `loadYamlStream` that resolves
/// to a `package:yaml` import.
///
/// A name resolves to `package:yaml` when it is written bare and a
/// `package:yaml` import without a prefix exposes it, or when it is written
/// as `prefix.name` and `prefix` names a `package:yaml` import that exposes
/// it. `show` and `hide` combinators are honored. Members of other types,
/// such as `YamlLimits.loadYaml`, are ignored. The detector reads the
/// unresolved syntax tree, so a local declaration that shadows an imported
/// loader name is reported too.
List<ConventionViolation> findRawYamlLoads(Source source) {
  final List<_YamlImport> imports = [
    for (final ImportDirective directive in source.unit.directives.whereType<ImportDirective>())
      if (directive.uri.stringValue?.startsWith('package:yaml/') ?? false) _YamlImport(directive),
  ];
  if (imports.isEmpty) {
    return const [];
  }
  final List<ConventionViolation> violations = [];
  for (final SimpleIdentifier identifier in source.nodes.whereType<SimpleIdentifier>()) {
    final String name = identifier.name;
    if (!_yamlLoaderNames.contains(name)) {
      continue;
    }
    final _Reference? reference = _reference(identifier);
    if (reference == null) {
      continue;
    }
    final bool fromYaml = imports.any(
      (import) => import.prefix == reference.prefix && import.exposes(name),
    );
    if (fromYaml) {
      final written = reference.prefix == null ? name : '${reference.prefix}.$name';
      final usage = reference.isCall ? 'calls $written' : 'tears off $written';
      violations.add(
        source.violationAt(
          identifier.offset,
          '$usage from package:yaml instead of YamlLimits.loadYaml',
        ),
      );
    }
  }
  return violations;
}

/// Reports each call or tear-off of `Pubspec.parse` in [source] when it
/// imports `package:pubspec_parse`, with or without a prefix.
///
/// `Pubspec.parse` loads its YAML with `package:yaml` and no limits.
List<ConventionViolation> findRawPubspecParses(Source source) {
  final bool importsPubspecParse = source.unit.directives.whereType<ImportDirective>().any(
    (directive) => directive.uri.stringValue?.startsWith('package:pubspec_parse/') ?? false,
  );
  if (!importsPubspecParse) {
    return const [];
  }
  return [
    for (final SimpleIdentifier identifier in source.nodes.whereType<SimpleIdentifier>())
      if (identifier.name == 'parse' && _pubspecMemberOwner(identifier) == 'Pubspec')
        source.violationAt(
          identifier.offset,
          'parses with Pubspec.parse instead of YamlLimits.loadPubspec',
        ),
  ];
}

/// The name of the type that [node] is a member of, when [node] is written
/// as `Type.member` or `prefix.Type.member`.
String? _pubspecMemberOwner(SimpleIdentifier node) => switch (node.parent) {
  MethodInvocation(:final SimpleIdentifier methodName, :final Expression? target)
      when methodName == node =>
    _typeName(target),
  PrefixedIdentifier(:final SimpleIdentifier identifier, :final SimpleIdentifier prefix)
      when identifier == node =>
    prefix.name,
  PropertyAccess(:final SimpleIdentifier propertyName, :final Expression? target)
      when propertyName == node =>
    _typeName(target),
  _ => null,
};

String? _typeName(Expression? target) => switch (target) {
  SimpleIdentifier(:final String name) => name,
  PrefixedIdentifier(:final SimpleIdentifier identifier) => identifier.name,
  _ => null,
};

/// How an identifier is written: bare or behind a simple prefix, and
/// whether it is the name of a call.
typedef _Reference = ({String? prefix, bool isCall});

/// The reference [node] makes, or null when it cannot name a top-level
/// function: a doc comment reference, a `show` or `hide` name, a
/// named-argument label, or a member accessed on any expression other than a
/// simple identifier.
_Reference? _reference(SimpleIdentifier node) {
  if (node.thisOrAncestorOfType<CommentReference>() != null) {
    return null;
  }
  return switch (node.parent) {
    Combinator() || Label() => null,
    MethodInvocation(:final SimpleIdentifier methodName, :final Expression? target)
        when methodName == node =>
      switch (target) {
        null => (prefix: null, isCall: true),
        SimpleIdentifier(:final String name) => (prefix: name, isCall: true),
        _ => null,
      },
    PrefixedIdentifier(:final SimpleIdentifier identifier, :final SimpleIdentifier prefix)
        when identifier == node =>
      (prefix: prefix.name, isCall: false),
    PropertyAccess(:final SimpleIdentifier propertyName) when propertyName == node => null,
    _ => (prefix: null, isCall: false),
  };
}

/// A `package:yaml` import: its prefix and which names it exposes.
class _YamlImport {
  _YamlImport(ImportDirective directive)
    : prefix = directive.prefix?.name,
      _combinators = directive.combinators;

  final String? prefix;
  final List<Combinator> _combinators;

  /// Whether the import's `show` and `hide` combinators let [name] through.
  bool exposes(String name) => _combinators.every(
    (combinator) => switch (combinator) {
      ShowCombinator(:final shownNames) => shownNames.any((shown) => shown.name == name),
      HideCombinator(:final hiddenNames) => hiddenNames.every((hidden) => hidden.name != name),
    },
  );
}
