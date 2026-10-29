// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/readme_anchors.dart';
import 'src/repo_paths.dart';

const String _pubDevPackagesUrl = 'https://pub.dev/packages/';

/// The package page on pub.dev, which shows this package's README.
const String _readmeUrl = '${_pubDevPackagesUrl}skills_lint';

/// A link from a page outside this repository into this package's docs.
///
/// `target` is the full URL the outside page links to. `linkedFrom` is the
/// URL of the page that contains the link: the page to update if the target
/// is removed on purpose.
typedef ExternalLink = ({String target, String linkedFrom});

/// Links into this package's docs that pages outside this repository rely on.
///
/// Add an entry when another page starts linking to this package. To remove
/// or rename a linked README section on purpose, update the `linkedFrom` page
/// first, then delete the entry. A `target` without an anchor is the package
/// page itself, which keeps working while the package keeps its name.
const List<ExternalLink> externalLinks = [
  (target: '$_readmeUrl#rule-precedence', linkedFrom: _dartDevPubPackageSkills),
  (target: '$_readmeUrl#built-in-rules', linkedFrom: _dartDevPubPackageSkills),
  (target: '$_readmeUrl#3-custom-rules', linkedFrom: _dartDevPubPackageSkills),
  (target: '$_readmeUrl#recipes', linkedFrom: _dartDevPubPackageSkills),
  (target: _readmeUrl, linkedFrom: _dartDevPubPackageSkills),
  (target: _readmeUrl, linkedFrom: 'https://dart.dev/ai/package-skills'),
  (target: _readmeUrl, linkedFrom: 'https://docs.flutter.dev/ai/tools'),
];

const String _dartDevPubPackageSkills = 'https://dart.dev/tools/pub/package-skills';

/// Fails when a link in [externalLinks] would stop working.
///
/// pub.dev serves the package page at `$_readmeUrl`, from the package name,
/// renders README.md there, and derives each heading's anchor from its text.
/// If the package is renamed, or a linked heading is renamed or removed, the
/// outside link breaks or no longer jumps to its section, and nothing else in
/// this repo notices. These tests read local files only and make no network
/// requests.
void main() {
  test('the package name still matches externally linked package URLs', () {
    // Read the pubspec `dart test` runs in rather than the one behind
    // packageRoot: after a rename, package:skills_lint resolves elsewhere.
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(
      '$_pubDevPackagesUrl${pubspec['name']}',
      _readmeUrl,
      reason:
          'Pages outside this repo link to $_readmeUrl:\n'
          '${{for (final ExternalLink link in externalLinks) link.linkedFrom}.join('\n')}',
    );
  });

  test('every externally linked README anchor still has a heading', () {
    final String readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
    final Set<String> anchors = headingAnchors(readme).toSet();
    final List<String> broken = [
      for (final ExternalLink link in externalLinks)
        if (_readmeAnchor(link.target) case final String anchor when !anchors.contains(anchor))
          '${link.target}\n  linked from ${link.linkedFrom}',
    ];
    expect(
      broken,
      isEmpty,
      reason:
          'README.md no longer has a heading for these links:\n'
          '${broken.join('\n')}\n\n'
          'Restore the heading text. If the section was removed on purpose, '
          'update the linking page, then delete the entry from externalLinks.',
    );
  });
}

/// The README anchor in [target], or `null` when [target] is the package page
/// itself.
///
/// [target] must be `$_readmeUrl` or `$_readmeUrl#<anchor>`.
String? _readmeAnchor(String target) {
  if (target == _readmeUrl) {
    return null;
  }
  const prefix = '$_readmeUrl#';
  if (!target.startsWith(prefix) || target.length == prefix.length) {
    fail('$target is not $_readmeUrl or a $prefix<anchor> link.');
  }
  return target.substring(prefix.length);
}
