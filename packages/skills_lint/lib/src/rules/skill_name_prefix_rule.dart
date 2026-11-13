// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import '../fixable_rule.dart';
import '../models/analysis_severity.dart';
import '../models/parameter_constraint.dart';
import '../models/skill_context.dart';
import '../models/skill_rule.dart';
import '../models/source_region.dart';
import '../models/validation_error.dart';
import '../name_prefix.dart';
import 'name_format_rule.dart';

/// Enforces that a skill's `name` starts with a configured prefix.
///
/// A name passes when it equals [prefix] or starts with [prefix] followed by
/// a hyphen, as in `myproject` or `myproject-setup` for prefix `myproject`.
class SkillNamePrefixRule extends SkillRule implements FixableRule {
  SkillNamePrefixRule({this.severity = defaultSeverity, this.prefix});

  static const String ruleName = 'skill-name-prefix';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  /// The rule parameter that sets [prefix].
  static const String prefixParameter = 'value';

  /// Restricts [prefixParameter] to valid skill names, so that a name can
  /// start with it.
  static const prefixConstraint = ParameterConstraint(
    description: 'a valid skill name',
    accepts: _isValidSkillName,
  );

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  /// The prefix every skill name must start with.
  ///
  /// When it is `null` or empty, the rule reports each skill until the
  /// prefix is set.
  final String? prefix;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final YamlMap? yaml = context.parsedYaml;
    if (context.yamlParsingError != null || yaml == null) {
      return const [];
    }

    final YamlNode? nameNode = yaml.nodes['name'];
    final String skillName = nameNode?.value?.toString().trim() ?? '';
    if (skillName.isEmpty) {
      return const [];
    }

    final SourceRegion? region = context.yamlNodeToRegion(nameNode);
    final String? prefix = this.prefix;
    if (prefix == null || prefix.isEmpty) {
      return [_buildMissingPrefixError(region)];
    }
    if (hasNamePrefix(skillName, prefix)) {
      return const [];
    }
    return [
      _buildMissingNamePrefixError(
        skillName: skillName,
        prefix: prefix,
        suggestedName: suggestPrefixedName(currentName: skillName, prefix: prefix),
        region: region,
      ),
    ];
  }

  ValidationError _buildMissingPrefixError(SourceRegion? region) {
    const flag = '--$ruleName-$prefixParameter';
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      message:
          'The $ruleName rule has no prefix to check. Set its $prefixParameter '
          'parameter in skills_lint.yaml or pass $flag, or disable the rule.',
      markdownMessage:
          '**The `$ruleName` rule has no prefix to check.**\n\n'
          '**How to fix:**\n'
          '- Set its `$prefixParameter` parameter in `skills_lint.yaml`, or\n'
          '- Pass `$flag`, or\n'
          '- Disable the `$ruleName` rule.',
      region: region,
    );
  }

  ValidationError _buildMissingNamePrefixError({
    required String skillName,
    required String prefix,
    required String suggestedName,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      message:
          'Skill "$skillName" must be "$prefix" or start with "$prefix-". '
          'Suggested name: "$suggestedName".\n'
          'Fix by re-running your validation command with `--fix`.',
      markdownMessage:
          '**Skill name must be `$prefix` or start with `$prefix-`.**\n\n'
          '* **Current:** `$skillName`\n'
          '* **Suggested:** `$suggestedName`\n\n'
          '**How to fix:**\n'
          '```yaml\n'
          'name: $suggestedName\n'
          '```\n'
          '*(Or re-run validation with `--fix` to apply automatically).*',
      region: region,
    );
  }

  @override
  Future<String> fix(SkillContext context, {Set<String> ignoredSubjects = const {}}) async {
    final String? prefix = this.prefix;
    if (prefix == null || prefix.isEmpty) {
      return context.rawContent;
    }
    return renameSkillInFrontmatter(
      context.rawContent,
      (String currentName) => hasNamePrefix(currentName, prefix)
          ? null
          : suggestPrefixedName(currentName: currentName, prefix: prefix),
    );
  }
}

bool _isValidSkillName(Object value) => value is String && NameFormatRule.isValidSkillName(value);
