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

/// Enforces the naming conventions a project chooses for its skills.
///
/// [NameFormatRule] enforces what the Agent Skills specification requires.
/// This rule checks a skill's `name` against the parameters that are set:
/// - [prefix]: the name equals [prefix] or starts with [prefix] followed by
///   a hyphen, as in `myproject` or `myproject-setup`.
/// - [maxLength]: the name has at most [maxLength] characters.
class SkillNamingRule extends SkillRule implements FixableRule {
  SkillNamingRule({this.severity = defaultSeverity, this.prefix, this.maxLength});

  static const String ruleName = 'skill-naming';
  static const AnalysisSeverity defaultSeverity = AnalysisSeverity.disabled;

  /// The rule parameter that sets [prefix].
  static const String prefixParameter = 'prefix';

  /// The rule parameter that sets [maxLength].
  static const String maxLengthParameter = 'max-length';

  /// Restricts [prefixParameter] to valid skill names, so that a name can
  /// start with it.
  static const prefixConstraint = ParameterConstraint(
    description: 'a valid skill name',
    accepts: _isValidSkillName,
  );

  /// Restricts [maxLengthParameter] to integers from 1 to
  /// [NameFormatRule.maxNameLength].
  static const maxLengthConstraint = ParameterConstraint(
    description: 'an integer from 1 to ${NameFormatRule.maxNameLength}',
    accepts: _isNameLength,
  );

  @override
  String get name => ruleName;

  @override
  final AnalysisSeverity severity;

  /// The prefix every skill name must start with, or `null` to not check
  /// prefixes.
  final String? prefix;

  /// The most characters a skill name can have, or `null` to not check
  /// lengths.
  final int? maxLength;

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
    final String? prefix = _prefixOrNull;
    final int? maxLength = this.maxLength;
    if (prefix == null && maxLength == null) {
      return [_buildNoParameterError(region)];
    }

    final errors = <ValidationError>[];
    if (prefix != null && !hasNamePrefix(skillName, prefix)) {
      errors.add(
        _buildPrefixError(
          skillName: skillName,
          prefix: prefix,
          suggestedName: suggestPrefixedName(currentName: skillName, prefix: prefix),
          region: region,
        ),
      );
    }
    if (maxLength != null && skillName.length > maxLength) {
      errors.add(_buildLengthError(skillName: skillName, maxLength: maxLength, region: region));
    }
    return errors;
  }

  String? get _prefixOrNull {
    final String? prefix = this.prefix;
    return prefix == null || prefix.isEmpty ? null : prefix;
  }

  /// Whether `--fix` can rename a skill to [suggestedName] without breaking
  /// [maxLength].
  bool _fitsMaxLength(String suggestedName) {
    final int? maxLength = this.maxLength;
    return maxLength == null || suggestedName.length <= maxLength;
  }

  ValidationError _buildNoParameterError(SourceRegion? region) {
    const prefixFlag = '--$ruleName-$prefixParameter';
    const maxLengthFlag = '--$ruleName-$maxLengthParameter';
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      message:
          'The $ruleName rule has no convention to check. Set its $prefixParameter or '
          '$maxLengthParameter parameter in skills_lint.yaml or pass $prefixFlag or '
          '$maxLengthFlag, or disable the rule.',
      markdownMessage:
          '**The `$ruleName` rule has no convention to check.**\n\n'
          '**How to fix:**\n'
          '- Set its `$prefixParameter` or `$maxLengthParameter` parameter in '
          '`skills_lint.yaml`, or\n'
          '- Pass `$prefixFlag` or `$maxLengthFlag`, or\n'
          '- Disable the `$ruleName` rule.',
      region: region,
    );
  }

  ValidationError _buildPrefixError({
    required String skillName,
    required String prefix,
    required String suggestedName,
    required SourceRegion? region,
  }) {
    if (!_fitsMaxLength(suggestedName)) {
      final byHand =
          'Rename it by hand to at most $maxLength characters. `--fix` skips this rename, '
          'because "$suggestedName" is longer than the $maxLengthParameter.';
      return ValidationError(
        ruleId: name,
        severity: severity,
        file: SkillContext.skillFileName,
        message: 'Skill "$skillName" must be "$prefix" or start with "$prefix-". $byHand',
        subject: prefixParameter,
        markdownMessage:
            '**Skill name must be `$prefix` or start with `$prefix-`.**\n\n'
            '* **Current:** `$skillName`\n\n'
            '**How to fix:**\n'
            '$byHand',
        region: region,
      );
    }
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      message:
          'Skill "$skillName" must be "$prefix" or start with "$prefix-". '
          'Suggested name: "$suggestedName".\n'
          'Fix by re-running your validation command with `--fix`.',
      subject: prefixParameter,
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

  ValidationError _buildLengthError({
    required String skillName,
    required int maxLength,
    required SourceRegion? region,
  }) {
    return ValidationError(
      ruleId: name,
      severity: severity,
      file: SkillContext.skillFileName,
      message:
          'Skill "$skillName" is ${skillName.length} characters; '
          'the $maxLengthParameter is $maxLength. Shorten the `name:` field in SKILL.md.',
      subject: maxLengthParameter,
      markdownMessage:
          "**Skill name is longer than the project's $maxLengthParameter.**\n\n"
          '* **Current:** `$skillName` (**${skillName.length}** characters)\n'
          '* **Limit:** **$maxLength** characters\n\n'
          '**How to fix:**\n'
          'Shorten the `name:` field in `SKILL.md`.',
      region: region,
    );
  }

  /// Renames the skill to start with [prefix].
  ///
  /// Leaves the skill unchanged when no prefix is set, when [ignoredSubjects]
  /// holds [prefixParameter], or when the suggested name is longer than
  /// [maxLength].
  @override
  Future<String> fix(SkillContext context, {Set<String> ignoredSubjects = const {}}) async {
    // Names longer than maxLength aren't shortened: the shorter name is the
    // author's choice.
    final String? prefix = _prefixOrNull;
    if (prefix == null || ignoredSubjects.contains(prefixParameter)) {
      return context.rawContent;
    }
    return renameSkillInFrontmatter(context.rawContent, (String currentName) {
      if (hasNamePrefix(currentName, prefix)) {
        return null;
      }
      final String suggestedName = suggestPrefixedName(currentName: currentName, prefix: prefix);
      return _fitsMaxLength(suggestedName) ? suggestedName : null;
    });
  }
}

bool _isValidSkillName(Object value) => value is String && NameFormatRule.isValidSkillName(value);

bool _isNameLength(Object value) =>
    value is int && value >= 1 && value <= NameFormatRule.maxNameLength;
