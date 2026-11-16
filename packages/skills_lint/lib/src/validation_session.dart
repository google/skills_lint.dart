// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'config_parser.dart';
import 'missing_target_diagnostic.dart';
import 'models/analysis_severity.dart';
import 'models/check_type.dart';
import 'models/fix_outcome.dart';
import 'models/ignore_entry.dart';
import 'models/output_format.dart';
import 'models/pub_archive.dart';
import 'models/rule_config.dart';
import 'models/sarif/sarif.dart';
import 'models/skill_context.dart';
import 'models/skill_rule.dart';
import 'models/skills_ignores.dart';
import 'models/skipped_fix.dart';
import 'models/validation_error.dart';
import 'path_utils.dart';
import 'pub_archive_loader.dart';
import 'reporters/reporters.dart';
import 'rule_registry.dart';
import 'rules/pub_archive_includes_skill_rule.dart';
import 'skill_fixer.dart';
import 'unknown_rule_names.dart';
import 'validator.dart';
import 'write/ignore_file_writer.dart';
import 'write/skill_writer.dart';
import 'write/write_boundary.dart';

export 'write/ignore_file_writer.dart' show defaultIgnoreFileName;

// TODO(reidbaker): Remove deprecated IgnorePathFor typedef in 0.6.0.
/// The ignore file path for a skill in [skillDir].
@Deprecated('Unused; will be removed in 0.6.0.')
typedef IgnorePathFor = String Function(Directory skillDir);

/// The [IgnoreFileTarget] for a skill in the given directory.
typedef _IgnoreTargetFor = IgnoreFileTarget Function(Directory skillDir);

/// Per-invocation state and orchestration for skill validation.
///
/// One session is constructed per CLI invocation (or embedded call). The
/// session aggregates configuration parameters, custom rules, ignores, and CLI overrides,
/// then orchestrates the validation of multiple target skill directories.
///
/// ## Path canonicalization contract
///
/// Pass paths in whatever form you have them. The session resolves each one as
/// it arrives, then compares absolute paths for the rest of the run, so a
/// result never depends on the directory the process started in.
///
/// Callers invoke [processIndividualSkill] for each `--skill` path and
/// [processSkillRoot] for each `--skills-directory` path, then optionally
/// [reportNoSkillsValidated] to emit the "no skills found" diagnostics.
/// The failure state of the session is exposed via [anyFailed] and [anySkillsValidated].
class ValidationSession {
  /// Creates a validation session with the specified configuration, overrides, and rules.
  ///
  /// * [config] is the parsed YAML configuration file settings.
  /// * [resolvedRuleConfigs] maps rule names to rule configuration patches (e.g., CLI-passed flags).
  /// * [ignoreFileOverride] specifies a custom file path containing lint ignores to load.
  /// * [customRules] contains programmatically injected custom skill rule checks.
  /// * [printWarnings] controls whether warnings are printed to stdout.
  /// * [fastFail] controls whether validation stops immediately on the first error.
  /// * [quiet] controls whether success messages and other info logs are silenced.
  /// * [generateBaseline] controls whether the validation should output/update baseline ignores.
  /// * [fix] controls whether to apply fixable rule modifications directly to files.
  /// * [fixApply] is the deprecated flag indicating if fixes should be automatically applied.
  // TODO(reidbaker): Remove deprecated fixApply parameter on next major version bump.
  /// * [format] specifies the output format for diagnostics ([OutputFormat.text], [OutputFormat.json], [OutputFormat.sarif]).
  /// * [allowWrite] lists directories from `--allow-write` that every
  ///   target's writes may also land in.
  /// * [pubArchiveLoader] lists the files pub publishes. Tests pass one with a
  ///   fake process runner.
  /// * [skillWriter] builds the [SkillWriter] that does the `--fix` file I/O.
  ///   Tests pass one that fails in ways the file system can't easily cause.
  ValidationSession({
    required this.config,
    // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/75
    @Deprecated('Use resolvedRuleConfigs instead')
    Map<String, AnalysisSeverity> resolvedRules = const {},
    Map<String, RuleConfigPatch> resolvedRuleConfigs = const {},
    required String? ignoreFileOverride,
    required this.customRules,
    required this.printWarnings,
    required this.fastFail,
    required this.quiet,
    required this.generateBaseline,
    required this.fix,
    // TODO(reidbaker): Remove deprecated fixApply parameter on next major version bump.
    required this.fixApply,
    this.format = OutputFormat.text,
    List<String> allowWrite = const [],
    @visibleForTesting PubArchiveLoader? pubArchiveLoader,
    @visibleForTesting SkillWriter Function(Reporter reporter) skillWriter = SkillWriter.new,
  }) : _pubArchiveLoader = pubArchiveLoader ?? PubArchiveLoader(),
       _skillWriterFor = skillWriter,
       resolvedRuleConfigs = mergeDeprecatedRules(resolvedRules, resolvedRuleConfigs),
       ignoreFileOverride = _ingestOptionalPath(ignoreFileOverride),
       _allowWrite = [for (final String path in allowWrite) _ingestPath(path)],
       _normalizedDirectoryConfigs = [
         for (final dc in [...config.directoryConfigs, ...config.individualSkillConfigs])
           (
             normalizedPath: _ingestPath(dc.path),
             normalizedIgnoreFile: _ingestOptionalPath(dc.ignoreFile),
             config: dc,
           ),
       ] {
    final reporter = Reporter.fromFormat(format, quiet: quiet, printWarnings: printWarnings);
    _reporter = reporter;
    _ignoreWriter = IgnoreFileWriter(reporter);
  }

  /// Anchors an externally supplied [rawPath] to the working directory.
  ///
  /// This is the only path ingestion point in the session. Every other member
  /// of this class works with the absolute, normalized paths it produces, so
  /// no other code path in this file may canonicalize. See [canonicalizePath]
  /// for the boundary contract.
  static String _ingestPath(String rawPath) =>
      canonicalizePath(rawPath, baseDirectory: Directory.current.path);

  /// The nullable companion to [_ingestPath].
  static String? _ingestOptionalPath(String? rawPath) =>
      rawPath == null ? null : _ingestPath(rawPath);

  /// Converts deprecated severity-only [deprecatedRules] into config
  /// patches and merges them with [configPatches].
  ///
  /// Returns an empty, unmodifiable const map when both inputs are empty.
  /// Throws an [ArgumentError] if both maps are non-empty.
  static Map<String, RuleConfigPatch> mergeDeprecatedRules(
    Map<String, AnalysisSeverity> deprecatedRules,
    Map<String, RuleConfigPatch> configPatches,
  ) {
    if (deprecatedRules.isEmpty && configPatches.isEmpty) {
      return const {};
    }
    if (deprecatedRules.isNotEmpty && configPatches.isNotEmpty) {
      throw ArgumentError(
        'Cannot specify both deprecated resolvedRules and new resolvedRuleConfigs. '
        'Please migrate all overrides to resolvedRuleConfigs.',
      );
    }
    final merged = Map<String, RuleConfigPatch>.from(configPatches);
    for (final MapEntry<String, AnalysisSeverity> entry in deprecatedRules.entries) {
      merged[entry.key] = RuleConfigPatch(severity: entry.value);
    }
    return merged;
  }

  final Configuration config;
  final Map<String, RuleConfigPatch> resolvedRuleConfigs;
  final String? ignoreFileOverride;
  final List<SkillRule> customRules;
  final bool printWarnings;
  final bool fastFail;
  final bool quiet;
  final bool generateBaseline;
  final bool fix;
  // TODO(reidbaker): Remove deprecated fixApply field on next major version bump.
  final bool fixApply;
  final OutputFormat format;

  /// The anchored directories from `--allow-write`.
  final List<String> _allowWrite;

  late final Reporter _reporter;
  late final IgnoreFileWriter _ignoreWriter;
  final PubArchiveLoader _pubArchiveLoader;

  final SkillWriter Function(Reporter reporter) _skillWriterFor;

  final List<ValidationResult> _results = [];
  final List<_ValidatedSkill> _validatedSkills = [];
  final Set<String> _renamedIgnorePaths = {};
  bool _anySkillRenamed = false;

  /// All validation results collected during this session.
  List<ValidationResult> get results => List.unmodifiable(_results);

  /// [config]'s targets with each `path` and `ignore_file` anchored once.
  ///
  /// `config` is static for the lifetime of a session, so the anchoring cost is
  /// paid up front instead of once per skill in [resolveRuleConfigsForPath] and
  /// [resolveIgnoreFile].
  final List<({String normalizedPath, String? normalizedIgnoreFile, LintTargetConfig config})>
  _normalizedDirectoryConfigs;

  bool _anyFailed = false;

  /// Whether `--fix` failed to write a skill's fixes, which fails the run
  /// whatever the skill's diagnostics.
  bool _fixWriteFailed = false;
  bool _anySkillsValidated = false;

  /// Whether `--fix` refused a write or rename because it would land outside a
  /// [WriteBoundary].
  bool _fixWriteRefused = false;

  bool get _writeRefused => _fixWriteRefused || _ignoreWriter.writeRefused;

  bool get anyFailed => _anyFailed || _fixWriteFailed || _writeRefused;

  bool get anySkillsValidated => _anySkillsValidated;

  /// Reports that the [kind] of target at [normalizedPath] does not exist,
  /// explained with where it came from, and marks the session failed.
  void _reportMissingTarget(
    MissingTargetKind kind,
    String normalizedPath, {
    required LintTargetConfig? declaredBy,
    required String? cliText,
  }) {
    final MissingTargetDiagnostic diagnostic = missingTargetDiagnostic(
      kind: kind,
      resolvedPath: normalizedPath,
      workingDirectory: Directory.current.path,
      declaration: declaredBy == null ? null : declarationOf(declaredBy),
      cliText: cliText,
    );
    _reporter.onNoSkillsFound(diagnostic.text);
    _results.add(
      ValidationResult(
        validationErrors: [
          ValidationError(
            ruleId: Validator.pathDoesNotExist,
            file: diagnostic.file,
            message: diagnostic.text,
            markdownMessage: diagnostic.markdown,
            region: diagnostic.region,
            severity: AnalysisSeverity.error,
          ),
        ],
      ),
    );
    _anyFailed = true;
  }

  /// Validates a single skill directory passed via `--skill` / `-s`.
  ///
  /// Returns `true` if the caller should continue iterating, `false` to
  /// stop. Only a real validation failure under [fastFail] returns `false`;
  /// a missing directory contributes to [anyFailed] but still allows the
  /// caller to continue.
  ///
  /// Pass [declaredBy] when the path came from a configuration target, or
  /// [cliText] with the path as typed when it came from the command line, so
  /// that a missing directory is explained in terms the user wrote.
  Future<bool> processIndividualSkill(
    String skillPath, {
    LintTargetConfig? declaredBy,
    String? cliText,
  }) async {
    final String normalizedSkillPath = _ingestPath(skillPath);
    _reporter.onDirectoryEvaluating(normalizedSkillPath);
    final skillDir = Directory(normalizedSkillPath);

    if (!skillDir.existsSync()) {
      _reportMissingTarget(
        MissingTargetKind.skill,
        normalizedSkillPath,
        declaredBy: declaredBy,
        cliText: cliText,
      );
      return true;
    }

    final Map<String, RuleConfig> resolvedConfigs = resolveRuleConfigsForPath(normalizedSkillPath);
    final validator = Validator(ruleConfigs: resolvedConfigs, customRules: customRules);
    final boundary = WriteBoundary.forSkill(
      normalizedSkillPath,
      configDirectory: declaredBy == null ? null : declarationOf(declaredBy)?.anchorDirectory,
      configAllowed: declaredBy?.writeAllow ?? const [],
      allowed: _allowWrite,
    );
    final IgnoreFileTarget ignoreTarget = _resolveIgnoreTarget(
      normalizedSkillPath,
      defaultDirectory: skillDir,
      targetBoundary: boundary,
    );
    final SkillsIgnores ignores = await _ignoreWriter.load(ignoreTarget);

    _anySkillsValidated = true;
    // The workflow adds no results, so this skill's result lands at
    // [resultIndex] when it is added below.
    final int resultIndex = _results.length;
    final ValidationResult finalResult = await _runValidationWorkflow(
      skillDir: skillDir,
      boundary: boundary,
      validator: validator,
      ignores: ignores,
      ignoreTargetFor: ignoreTarget.afterSkillRename,
      resultIndex: resultIndex,
    );
    _results.add(finalResult);

    final Directory effectiveSkillDir = finalResult.context?.directory ?? skillDir;
    final String effectiveSkillName = p.basename(effectiveSkillDir.path);
    final String effectiveIgnorePath = ignoreTarget.afterSkillRename(effectiveSkillDir).path;
    if (generateBaseline) {
      await _ignoreWriter.saveBaseline(effectiveIgnorePath, ignores);
    } else {
      if (_renamedIgnorePaths.remove(effectiveIgnorePath)) {
        await _ignoreWriter.saveBaseline(effectiveIgnorePath, ignores);
      }
      final String fullPath = p.absolute(effectiveSkillDir.path);
      for (final IgnoreEntry ignore in ignores.skills[effectiveSkillName] ?? const []) {
        if (!ignore.used) {
          _reporter.onStaleIgnoreFound(
            ruleId: ignore.ruleId,
            skillName: effectiveSkillName,
            fullPath: fullPath,
            subject: ignore.subject,
          );
        }
      }
    }

    if (!finalResult.isValid) {
      _anyFailed = true;
      if (fastFail) {
        return false;
      }
    }
    return true;
  }

  /// Validates every skill directory under a root passed via
  /// `--skills-directory` / `-d`.
  ///
  /// Returns `true` if the caller should continue iterating, `false` to
  /// stop. Missing-root and listing-failure errors contribute to [anyFailed]
  /// but allow the caller to continue. After a successful iteration, returns
  /// `false` if [fastFail] is set and any failure has accumulated across the
  /// run so far.
  ///
  /// [declaredBy] and [cliText] describe where [rootPath] came from, as for
  /// [processIndividualSkill].
  Future<bool> processSkillRoot(
    String rootPath, {
    LintTargetConfig? declaredBy,
    String? cliText,
  }) async {
    final String normalizedRootPath = _ingestPath(rootPath);
    _reporter.onDirectoryEvaluating(normalizedRootPath);
    final rootDir = Directory(normalizedRootPath);

    if (!rootDir.existsSync()) {
      _reportMissingTarget(
        MissingTargetKind.skillsRoot,
        normalizedRootPath,
        declaredBy: declaredBy,
        cliText: cliText,
      );
      return true;
    }

    List<FileSystemEntity> entities;
    try {
      entities = await rootDir.list().toList();
    } on FileSystemException {
      _reporter.onDirectoryError(
        normalizedRootPath,
        'Failed to list children of: $normalizedRootPath',
      );
      _results.add(
        ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: Validator.pathDoesNotExist,
              file: normalizedRootPath,
              message: 'Failed to list children of: $normalizedRootPath',
              severity: AnalysisSeverity.error,
            ),
          ],
        ),
      );
      _anyFailed = true;
      return true;
    }
    entities.sort((a, b) => a.path.compareTo(b.path));

    // Keep a cache of loaded ignores to avoid loading/saving the same ignore file multiple times,
    // and to accumulate ignore usages correctly across all skills.
    final Map<String, SkillsIgnores> loadedIgnoresCache = {};
    var stoppedEarly = false;
    final boundary = WriteBoundary.forSkillsDirectory(
      normalizedRootPath,
      configDirectory: declaredBy == null ? null : declarationOf(declaredBy)?.anchorDirectory,
      configAllowed: declaredBy?.writeAllow ?? const [],
      allowed: _allowWrite,
    );

    for (final entity in entities) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }

      final bool shouldContinue = await _processRootSkillEntity(
        entity,
        rootDir,
        loadedIgnoresCache,
        boundary,
      );
      if (!shouldContinue) {
        stoppedEarly = true;
        break;
      }
    }

    await _finalizeIgnoresForRoot(loadedIgnoresCache, rootDir, stoppedEarly: stoppedEarly);
    await revalidateAfterRenames();

    return !(_anyFailed && fastFail);
  }

  /// Processes and validates a single skill directory ([entity]) located
  /// immediately inside a skills root directory ([rootDir]).
  Future<bool> _processRootSkillEntity(
    Directory entity,
    Directory rootDir,
    Map<String, SkillsIgnores> loadedIgnoresCache,
    WriteBoundary boundary,
  ) async {
    // [rootDir] is already anchored, so its children are absolute as well.
    final String normalizedSkillPath = p.normalize(entity.path);
    final Map<String, RuleConfig> resolvedConfigs = resolveRuleConfigsForPath(normalizedSkillPath);
    final validator = Validator(ruleConfigs: resolvedConfigs, customRules: customRules);
    final IgnoreFileTarget ignoreTarget = _resolveIgnoreTarget(
      normalizedSkillPath,
      defaultDirectory: rootDir,
      targetBoundary: boundary,
    );
    final SkillsIgnores ignores = await _getIgnoresForSkill(ignoreTarget, loadedIgnoresCache);

    _anySkillsValidated = true;
    // The workflow adds no results, so this skill's result lands at
    // [resultIndex] when it is added below.
    final int resultIndex = _results.length;
    final ValidationResult finalResult = await _runValidationWorkflow(
      skillDir: entity,
      boundary: boundary,
      validator: validator,
      ignores: ignores,
      ignoreTargetFor: (Directory _) => ignoreTarget,
      resultIndex: resultIndex,
    );
    _results.add(finalResult);

    if (!finalResult.isValid) {
      _anyFailed = true;
      if (fastFail) {
        return false;
      }
    }
    return true;
  }

  Future<SkillsIgnores> _getIgnoresForSkill(
    IgnoreFileTarget target,
    Map<String, SkillsIgnores> loadedIgnoresCache,
  ) async {
    final SkillsIgnores? cached = loadedIgnoresCache[target.path];
    if (cached != null) {
      _ignoreWriter.recordBoundary(target);
      return cached;
    }

    final SkillsIgnores ignores = await _ignoreWriter.load(target);
    loadedIgnoresCache[target.path] = ignores;
    return ignores;
  }

  Future<void> _finalizeIgnoresForRoot(
    Map<String, SkillsIgnores> loadedIgnoresCache,
    Directory rootDir, {
    required bool stoppedEarly,
  }) async {
    for (final MapEntry<String, SkillsIgnores> entry in loadedIgnoresCache.entries) {
      final String ignoreFilePath = entry.key;
      final SkillsIgnores ignores = entry.value;

      if (generateBaseline) {
        await _ignoreWriter.saveBaseline(ignoreFilePath, ignores);
        continue;
      }
      // A rename moved this file's keys, so it is saved even after a
      // fast-fail stop.
      if (_renamedIgnorePaths.remove(ignoreFilePath)) {
        await _ignoreWriter.saveBaseline(ignoreFilePath, ignores);
      }
      // After a fast-fail stop, unused entries may belong to skills this run
      // did not validate, so they are not known to be stale.
      if (!stoppedEarly) {
        _reportStaleIgnores(ignores, rootDir);
      }
    }
  }

  void _reportStaleIgnores(SkillsIgnores ignores, Directory rootDir) {
    for (final MapEntry<String, List<IgnoreEntry>> skillEntry in ignores.skills.entries) {
      final String skillName = skillEntry.key;
      for (final IgnoreEntry ignore in skillEntry.value) {
        if (!ignore.used) {
          final String fullPath = p.normalize(p.join(rootDir.path, skillName));
          _reporter.onStaleIgnoreFound(
            ruleId: ignore.ruleId,
            skillName: skillName,
            fullPath: fullPath,
            subject: ignore.subject,
          );
        }
      }
    }
  }

  /// Reports each entry in [Configuration.parsingErrors] of [config], and
  /// each rule name supplied in code that names no configurable rule, as a
  /// warning. Does not mark the session as failed.
  ///
  /// [ConfigParser] leaves unknown names out of what it parses, so any left in
  /// [config] came from a [Configuration] built in code.
  void reportConfigurationWarnings() => [
    ...config.parsingErrors,
    ...unknownRuleMessages(config.ruleConfigs, context: 'Global rules', customRules: customRules),
    for (final LintTargetConfig target in config.directoryConfigs)
      ...unknownRuleMessages(
        target.ruleConfigs,
        context: 'Directory entry rules for "${target.path}"',
        customRules: customRules,
      ),
    for (final LintTargetConfig target in config.individualSkillConfigs)
      ...unknownRuleMessages(
        target.ruleConfigs,
        context: 'Individual skill entry rules for "${target.path}"',
        customRules: customRules,
      ),
    ...unknownRuleMessages(
      resolvedRuleConfigs,
      context: 'resolvedRuleConfigs',
      customRules: customRules,
    ),
  ].forEach(_reporter.onConfigurationWarning);

  /// If no skills were validated across the whole run, emit appropriate
  /// diagnostics and mark the session as failed.
  void reportNoSkillsValidated(List<String> rootPaths) {
    if (_anySkillsValidated) {
      return;
    }

    var foundSingleSkillPassedToD = false;
    for (final rootPath in rootPaths) {
      final String expandedRootPath = _ingestPath(rootPath);
      final skillMdFile = File(p.join(expandedRootPath, SkillContext.skillFileName));
      if (skillMdFile.existsSync()) {
        final message =
            'Directory "$expandedRootPath" appears to be an individual skill. '
            'Use --skill / -s instead of -d / --skills-directory.';
        _reporter.onIndividualSkillHint(message);
        _results.add(
          ValidationResult(
            validationErrors: [
              ValidationError(
                ruleId: Validator.pathDoesNotExist,
                file: expandedRootPath,
                message: message,
                severity: AnalysisSeverity.error,
              ),
            ],
          ),
        );
        foundSingleSkillPassedToD = true;
      }
    }
    if (!foundSingleSkillPassedToD) {
      const message = 'No skills found to validate in the specified directories.';
      _reporter.onNoSkillsFound(message);
      _results.add(
        ValidationResult(
          validationErrors: [
            ValidationError(
              ruleId: Validator.pathDoesNotExist,
              file: rootPaths.isNotEmpty ? rootPaths.first : '.',
              message: message,
              severity: AnalysisSeverity.error,
            ),
          ],
        ),
      );
    }
    _anyFailed = true;
  }

  // TODO(reidbaker): https://github.com/google/skills_lint.dart/issues/75
  @Deprecated('Use resolveRuleConfigsForPath instead')
  Map<String, AnalysisSeverity> resolveRulesForPath(String path) {
    return resolveRuleConfigsForPath(
      path,
    ).map((String key, RuleConfig value) => MapEntry(key, value.severity));
  }

  @visibleForTesting
  Map<String, RuleConfig> resolveRuleConfigsForPath(String path) {
    final String normalizedPath = _ingestPath(path);
    final resolvedConfigs = <String, RuleConfig>{};

    // Initialize with all checks defaults
    for (final CheckType check in RuleRegistry.allChecks) {
      resolvedConfigs[check.name] = RuleConfig(severity: check.defaultSeverity);
    }

    void applyPatchMap(Map<String, RuleConfigPatch> patches) {
      for (final MapEntry<String, RuleConfigPatch> entry in patches.entries) {
        final String ruleName = entry.key;
        final RuleConfigPatch patch = entry.value;

        final RuleConfig base =
            resolvedConfigs[ruleName] ?? const RuleConfig(severity: AnalysisSeverity.disabled);
        resolvedConfigs[ruleName] = patch.applyTo(base);
      }
    }

    // 1. Global Config (from YAML)
    applyPatchMap(config.ruleConfigs);

    // 2. Path-Specific Config (from YAML)
    for (final ({String normalizedPath, String? normalizedIgnoreFile, LintTargetConfig config})
        entry
        in _normalizedDirectoryConfigs) {
      if (_targetCovers(entry.normalizedPath, normalizedPath)) {
        applyPatchMap(entry.config.ruleConfigs);
      }
    }

    // 3. Overrides (CLI flags or API caller) take highest precedence
    applyPatchMap(resolvedRuleConfigs);

    return resolvedConfigs;
  }

  @visibleForTesting
  String? resolveIgnoreFile(String path) {
    final String normalizedPath = _ingestPath(path);
    if (ignoreFileOverride != null) {
      return ignoreFileOverride;
    }
    return _matchingIgnoreConfig(normalizedPath)?.ignoreFilePath;
  }

  /// Whether a configuration target at [targetPath] applies to [skillPath].
  ///
  /// Both arguments are absolute, so the comparison is a pure path operation
  /// that never consults the working directory.
  static bool _targetCovers(String targetPath, String skillPath) =>
      isAtOrWithin(targetPath, skillPath);

  /// The last configuration target covering [normalizedSkillPath] that sets an
  /// `ignore_file`, paired with its anchored path, or `null` if none does.
  ({String ignoreFilePath, LintTargetConfig config})? _matchingIgnoreConfig(
    String normalizedSkillPath,
  ) {
    ({String ignoreFilePath, LintTargetConfig config})? matched;
    for (final (:normalizedPath, :normalizedIgnoreFile, :config) in _normalizedDirectoryConfigs) {
      if (_targetCovers(normalizedPath, normalizedSkillPath) && normalizedIgnoreFile != null) {
        matched = (ignoreFilePath: normalizedIgnoreFile, config: config);
      }
    }
    return matched;
  }

  /// Resolves the [IgnoreFileTarget] for [normalizedSkillPath], falling back to
  /// `skills_lint_ignore.json` in [defaultDirectory] when neither
  /// [ignoreFileOverride] nor a matching configuration entry specifies one.
  IgnoreFileTarget _resolveIgnoreTarget(
    String normalizedSkillPath, {
    required Directory defaultDirectory,
    required WriteBoundary targetBoundary,
  }) {
    final String? overridePath = ignoreFileOverride;
    if (overridePath != null) {
      return IgnoreFileTarget.fromOverride(overridePath);
    }
    final ({String ignoreFilePath, LintTargetConfig config})? configured = _matchingIgnoreConfig(
      normalizedSkillPath,
    );
    if (configured != null) {
      return IgnoreFileTarget.fromConfiguration(
        configured.ignoreFilePath,
        configDirectory: declarationOf(configured.config)?.anchorDirectory,
        allowWrite: _allowWrite,
      );
    }
    return IgnoreFileTarget.defaultIn(defaultDirectory, targetBoundary: targetBoundary);
  }

  /// Marks the errors in [result] that [ignores] covers.
  ///
  /// [skillDir] is the anchored directory of the skill under validation, and
  /// gives each error a portable name to compare against.
  void _applyIgnores(ValidationResult result, List<IgnoreEntry> ignores, Directory skillDir) {
    final List<({IgnoreEntry entry, String normalizedFileName})> preNormalizedIgnores = [
      for (final ignore in ignores)
        (entry: ignore, normalizedFileName: p.normalize(ignore.fileName)),
    ];

    for (final ValidationError error in result.validationErrors) {
      if (error.isIgnored) {
        continue;
      }
      final IgnoreEntry? entry = _entryFor(error, preNormalizedIgnores, skillDir);
      if (entry != null) {
        error.isIgnored = true;
        entry.used = true;
      }
    }
  }

  /// The entry in [ignores] that suppresses [error], or `null` if none does.
  ///
  /// An entry whose subject matches is used before a whole-file entry, so the
  /// order of entries in the ignore file doesn't change which one is reported
  /// stale.
  static IgnoreEntry? _entryFor(
    ValidationError error,
    List<({IgnoreEntry entry, String normalizedFileName})> ignores,
    Directory skillDir,
  ) {
    final String portableName = baselineFileName(error.file, skillDir);
    final String absoluteName = _absoluteErrorFile(error.file, skillDir);
    IgnoreEntry? wholeFile;
    for (final (:entry, :normalizedFileName) in ignores) {
      if (entry.ruleId != error.ruleId ||
          !_ignoreCovers(normalizedFileName, portableName, absoluteName)) {
        continue;
      }
      if (entry.subject == null) {
        wholeFile ??= entry;
      } else if (entry.subject == error.subject) {
        return entry;
      }
    }
    return wholeFile;
  }

  /// The `file_name` a baseline entry stores for an error that a rule reported
  /// on [errorFile] while validating [skillDir].
  ///
  /// For a path at or inside [skillDir], this is relative to it and uses `/`,
  /// such as `SKILL.md`, `references/guide.md`, or `.` for the directory
  /// itself. Any other path comes back normalized but otherwise unchanged.
  ///
  /// [pathContext] defaults to the host's.
  @visibleForTesting
  static String baselineFileName(String errorFile, Directory skillDir, {p.Context? pathContext}) {
    // Writing and matching both use this single source of truth, so they
    // agree on the in-repo form of a path. Using `/` lets a baseline match on
    // any machine and OS.
    final p.Context context = pathContext ?? p.context;
    final String normalized = context.normalize(errorFile);
    final String skillPath = context.normalize(skillDir.path);
    final bool atOrWithin =
        context.equals(skillPath, normalized) || context.isWithin(skillPath, normalized);
    if (context.isAbsolute(normalized) && atOrWithin) {
      return p.posix.joinAll(context.split(context.relative(normalized, from: skillPath)));
    }
    return normalized;
  }

  /// The portable form of a relative ignore entry name [fileName], with `/`
  /// between segments, so that an entry written with `\` on Windows still
  /// matches on any host.
  static String _portableIgnoreFileName(String fileName) =>
      p.posix.normalize(fileName.replaceAll(r'\', '/'));

  /// Where an error reported on [errorFile] sits on disk.
  static String _absoluteErrorFile(String errorFile, Directory skillDir) {
    final String normalized = p.normalize(errorFile);
    if (p.isAbsolute(normalized)) {
      return normalized;
    }
    return p.normalize(p.join(skillDir.path, normalized));
  }

  /// Whether [ignoreFileName] covers an error named [portableName].
  ///
  /// Baselines written before names were stored relative to the skill
  /// directory hold the path as it was spelled on the command line. Those
  /// entries keep matching while [absoluteName] ends with them.
  static bool _ignoreCovers(String ignoreFileName, String portableName, String absoluteName) {
    if (ignoreFileName == portableName ||
        (!p.isAbsolute(ignoreFileName) &&
            _portableIgnoreFileName(ignoreFileName) == portableName) ||
        p.equals(ignoreFileName, absoluteName)) {
      return true;
    }
    return _isPathSuffix(ignoreFileName, absoluteName);
  }

  /// Whether [candidate] names the trailing segments of [full].
  static bool _isPathSuffix(String candidate, String full) {
    final List<String> candidateSegments = p.split(candidate);
    final List<String> fullSegments = p.split(full);
    if (candidateSegments.isEmpty || candidateSegments.length >= fullSegments.length) {
      return false;
    }
    final int offset = fullSegments.length - candidateSegments.length;
    for (var i = 0; i < candidateSegments.length; i++) {
      if (candidateSegments[i] != fullSegments[offset + i]) {
        return false;
      }
    }
    return true;
  }

  /// Validates [skillDir], applies fixes if requested, and (when
  /// [generateBaseline] is set) updates [ignores] in memory with any new
  /// baseline entries for this skill. The caller is responsible for
  /// persisting [ignores] to disk once after all skills are processed —
  /// see [IgnoreFileWriter.saveBaseline].
  Future<ValidationResult> _runValidationWorkflow({
    required Directory skillDir,
    required WriteBoundary boundary,
    required Validator validator,
    required SkillsIgnores ignores,
    required _IgnoreTargetFor ignoreTargetFor,
    required int resultIndex,
  }) async {
    final String skillName = p.basename(skillDir.path);
    final List<IgnoreEntry> skillIgnores = ignores.skills[skillName] ?? [];

    final ValidationResult result = await _validateSingleSkill(
      skillDir: skillDir,
      validator: validator,
      skillIgnores: skillIgnores,
    );

    final ValidationResult finalResult = await _applyFixesIfNeeded(
      skillDir: skillDir,
      boundary: boundary,
      result: result,
      validator: validator,
      skillIgnores: skillIgnores,
      ignores: ignores,
      ignoreTargetFor: ignoreTargetFor,
    );

    final Directory effectiveSkillDir = finalResult.context?.directory ?? skillDir;
    final String effectiveName = p.basename(effectiveSkillDir.path);
    final String effectiveIgnorePath = ignoreTargetFor(effectiveSkillDir).path;
    _validatedSkills.add(
      _ValidatedSkill(
        resultIndex: resultIndex,
        skillDir: effectiveSkillDir,
        validator: validator,
        ignores: ignores,
        ignorePath: effectiveIgnorePath,
      ),
    );
    if (fixApply && identical(finalResult, result)) {
      _reporter.onSkillValidationComplete(result);
    }

    if (generateBaseline) {
      _updateBaselineForSkill(ignores, finalResult, effectiveName, effectiveSkillDir);
    }

    return finalResult;
  }

  Future<ValidationResult> _validateSingleSkill({
    required Directory skillDir,
    required Validator validator,
    required List<IgnoreEntry> skillIgnores,
  }) async {
    final String skillName = p.basename(skillDir.path);
    _reporter.onSkillEvaluating(skillName);
    final ValidationResult result = await validator.validate(
      skillDir,
      pubArchive: await _pubArchiveFor(skillDir, validator),
    );
    _applyIgnores(result, skillIgnores, skillDir);
    // With --fix, the result that counts is the one after the fixes are done.
    if (!fixApply) {
      _reporter.onSkillValidationComplete(result);
    }
    return result;
  }

  /// The files pub publishes for the package that holds [skillDir], or
  /// `null` when no rule in [validator] needs them.
  ///
  /// Building the archive runs `dart pub publish`, so the session does it
  /// only for skills that enable [PubArchiveIncludesSkillRule].
  Future<PubArchive?> _pubArchiveFor(Directory skillDir, Validator validator) async {
    final bool needsArchive = validator.rules.any(
      (SkillRule rule) => rule.name == PubArchiveIncludesSkillRule.ruleName,
    );
    if (!needsArchive) {
      return null;
    }
    return _pubArchiveLoader.archiveFor(skillDir);
  }

  Future<ValidationResult> _applyFixesIfNeeded({
    required Directory skillDir,
    required WriteBoundary boundary,
    required ValidationResult result,
    required Validator validator,
    required List<IgnoreEntry> skillIgnores,
    required SkillsIgnores ignores,
    required _IgnoreTargetFor ignoreTargetFor,
  }) async {
    if (!fix && !fixApply) {
      return result;
    }

    final SkillContext? context = result.context;
    if (context == null) {
      return result;
    }

    final skillMdFile = File(p.join(skillDir.path, SkillContext.skillFileName));
    if (!skillMdFile.existsSync()) {
      return result;
    }

    final SkillFixer fixer = _fixerFor(validator, skillIgnores, skillDir);
    final SkillWriter writer = _skillWriterFor(_reporter);
    final String currentDirectoryName = p.basename(skillDir.path);

    // Plan as if the directory can follow a changed `name`. If it can't, plan
    // again under the current name: the fixes that need the rename drop out,
    // and the others still land.
    FixOutcome outcome = await fixer.fix(result);
    // A plan that changes nothing writes nothing, so no boundary applies.
    ApplyResult applied = outcome.content == context.rawContent
        ? Applied(skillDir, renamed: false)
        : writer.preflight(skillDir, outcome.directoryName, boundary);
    if (applied is WriteRefused) {
      // SkillWriter reported why. Nothing is written for this skill, and the
      // run fails, with or without --dry-run.
      _fixWriteRefused = true;
      return result;
    }
    if (applied is RenameBlocked) {
      outcome = await _planWithoutRename(fixer, result, applied);
    }
    if (fixApply && outcome.content != context.rawContent) {
      applied = await writer.apply(skillDir, outcome.content, outcome.directoryName, boundary);
      if (applied is RenameBlocked) {
        // Only the rename failed, before anything was written.
        outcome = await _planWithoutRename(fixer, result, applied);
        if (outcome.content != context.rawContent) {
          // The new plan keeps the directory name, so this apply only writes.
          applied = await writer.apply(skillDir, outcome.content, outcome.directoryName, boundary);
        }
      }
    }

    for (final SkippedFix skipped in outcome.skippedFixes) {
      _reporter.onFixSkipped(currentDirectoryName, skipped);
    }
    if (!outcome.settled) {
      _reporter.onFixesDidNotSettle(skillName: currentDirectoryName, passes: SkillFixer.maxPasses);
    }
    if (outcome.content == context.rawContent) {
      return result;
    }

    if (!fixApply) {
      _reporter.onDryRunProposed(
        skillName: currentDirectoryName,
        targetSkillName: outcome.directoryName,
        originalContent: context.rawContent,
        currentContent: outcome.content,
      );
      _reporter.onFixedSkillValidationComplete(outcome.result, dryRun: true);
      return result;
    }

    return _finishApply(
      applied: applied,
      skillDir: skillDir,
      result: result,
      appliedRuleNames: outcome.appliedRuleNames,
      validator: validator,
      ignores: ignores,
      skillIgnores: skillIgnores,
      ignoreTargetFor: ignoreTargetFor,
    );
  }

  /// Updates the session after [SkillWriter.apply] returned [applied] for
  /// [skillDir], and returns the result that counts for the skill.
  Future<ValidationResult> _finishApply({
    required ApplyResult applied,
    required Directory skillDir,
    required ValidationResult result,
    required List<String> appliedRuleNames,
    required Validator validator,
    required SkillsIgnores ignores,
    required List<IgnoreEntry> skillIgnores,
    required _IgnoreTargetFor ignoreTargetFor,
  }) async {
    final String currentDirectoryName = p.basename(skillDir.path);
    // A failed write leaves the skill renamed only if undoing the rename
    // failed too.
    final Directory dirAfter = switch (applied) {
      Applied(:final Directory dir) || WriteFailed(:final Directory dir) => dir,
      RenameBlocked() || WriteRefused() => skillDir,
    };
    if (dirAfter.path != skillDir.path) {
      _onSkillRenamed(
        oldName: currentDirectoryName,
        renamedDir: dirAfter,
        ignores: ignores,
        oldIgnorePath: ignoreTargetFor(skillDir).path,
        newIgnoreTarget: ignoreTargetFor(dirAfter),
      );
    }
    if (applied is Applied) {
      _reporter.onFixesWritten(currentDirectoryName, ruleNames: appliedRuleNames);
    } else {
      // SKILL.md wasn't written. SkillWriter reported why, and the run fails.
      _fixWriteFailed = true;
      if (dirAfter.path == skillDir.path) {
        return result;
      }
    }
    // A skill left renamed is validated where it is, so the caller saves its
    // ignore file and the re-check finds it there.
    return _revalidateFixed(validator, dirAfter, ignores, skillIgnores);
  }

  /// Validates the skill in [dir] after `--fix` touched it, with the ignore
  /// entries stored under its current name, and reports the result.
  Future<ValidationResult> _revalidateFixed(
    Validator validator,
    Directory dir,
    SkillsIgnores ignores,
    List<IgnoreEntry> skillIgnores,
  ) async {
    final List<IgnoreEntry> fixedIgnores = ignores.skills[p.basename(dir.path)] ?? skillIgnores;
    final ValidationResult newResult = await validator.validate(
      dir,
      pubArchive: await _pubArchiveFor(dir, validator),
    );
    _applyIgnores(newResult, fixedIgnores, dir);
    _reporter.onFixedSkillValidationComplete(newResult);
    return newResult;
  }

  /// Updates the session after `--fix` renamed the skill [oldName] to
  /// [renamedDir].
  ///
  /// Moves the skill's ignore entries in [ignores] to the new name, marks the
  /// ignore file at [newIgnoreTarget] to be saved, drops the cached archive,
  /// which lists files by path, and asks for every skill to be checked again.
  void _onSkillRenamed({
    required String oldName,
    required Directory renamedDir,
    required SkillsIgnores ignores,
    required String oldIgnorePath,
    required IgnoreFileTarget newIgnoreTarget,
  }) {
    _anySkillRenamed = true;
    _pubArchiveLoader.clear();
    _ignoreWriter.moveRenamedIgnoreFile(oldIgnorePath: oldIgnorePath, newTarget: newIgnoreTarget);
    if (ignores.renameSkill(oldName, p.basename(renamedDir.path)) &&
        File(newIgnoreTarget.path).existsSync()) {
      _renamedIgnorePaths.add(newIgnoreTarget.path);
    }
  }

  /// The fixer for the skill in [skillDir], which counts only diagnostics
  /// that [skillIgnores] don't cover, and runs only the fixes enabled in
  /// [validator].
  SkillFixer _fixerFor(Validator validator, List<IgnoreEntry> skillIgnores, Directory skillDir) {
    final failedRuleNames = <String>{};
    return SkillFixer(
      validator: validator,
      mayFix: validator.fixEnabledFor,
      applyIgnores: (ValidationResult candidate) =>
          _applyIgnores(candidate, skillIgnores, skillDir),
      // A broken fixer throws on every pass and in every plan. Report it
      // once per skill.
      onFixFailed: (String ruleName, Object error) {
        if (failedRuleNames.add(ruleName)) {
          _reporter.onFixFailed(ruleName: ruleName, error: error);
        }
      },
    );
  }

  /// Plans the fixes for [result] again under the current directory name,
  /// after [blocked] stopped a planned rename.
  ///
  /// Each fix dropped because it needs the rename carries the reason from
  /// [blocked].
  static Future<FixOutcome> _planWithoutRename(
    SkillFixer fixer,
    ValidationResult result,
    RenameBlocked blocked,
  ) async {
    final FixOutcome replanned = await fixer.fix(result, canRename: false);
    return replanned.withSkippedFixes([
      for (final SkippedFix skipped in replanned.skippedFixes)
        if (skipped.needsRename) skipped.withReason(blocked.reason) else skipped,
    ]);
  }

  /// Mutates [ignores] in place to add baseline entries for any non-ignored
  /// errors in [result] under the [skillName] key. Pure in-memory operation
  /// — pair with [IgnoreFileWriter.saveBaseline] to persist changes.
  void _updateBaselineForSkill(
    SkillsIgnores ignores,
    ValidationResult result,
    String skillName,
    Directory skillDir,
  ) {
    final List<IgnoreEntry> entries = ignores.skills[skillName] ?? [];
    final Iterable<ValidationError> unsuppressed = result.validationErrors.where(
      (error) => !error.isIgnored,
    );
    for (final error in unsuppressed) {
      final newEntry = IgnoreEntry(
        ruleId: error.ruleId,
        fileName: baselineFileName(error.file, skillDir),
        subject: error.subject,
      );
      final bool alreadyListed = entries.any((entry) => _coverSameFindings(entry, newEntry));
      if (!alreadyListed) {
        entries.add(newEntry);
      }
    }

    if (entries.isNotEmpty) {
      ignores.skills[skillName] = entries;
    } else {
      ignores.skills.remove(skillName);
    }
  }

  /// Whether [a] and [b] suppress the same findings.
  static bool _coverSameFindings(IgnoreEntry a, IgnoreEntry b) =>
      a.ruleId == b.ruleId && a.fileName == b.fileName && a.subject == b.subject;

  /// Emits the formatted validation output (SARIF or JSON) to [sink] (defaults to [stdout]).
  void emitFormattedOutput([StringSink? sink]) {
    if (sink != null) {
      Reporter.fromFormat(format, out: sink).onSessionComplete(_results, customRules: customRules);
    } else {
      _reporter.onSessionComplete(_results, customRules: customRules);
    }
  }

  /// Formats all accumulated validation results according to [format].
  String formatOutput({bool pretty = true}) {
    switch (format) {
      case OutputFormat.sarif:
        return toSarifJson(pretty: pretty);
      case OutputFormat.json:
        return toJsonOutput(pretty: pretty);
      case OutputFormat.text:
        return toTextOutput();
    }
  }

  /// Formats the accumulated validation results as human-readable text.
  String toTextOutput() {
    final buffer = StringBuffer();
    final textReporter = TextReporter(
      out: buffer,
      err: buffer,
      quiet: quiet,
      printWarnings: printWarnings,
    );
    for (final ValidationResult result in _results) {
      final String skillName = result.context != null
          ? p.basename(result.context!.directory.path)
          : 'skill';
      textReporter.onSkillEvaluating(skillName);
      textReporter.onSkillValidationComplete(result);
    }
    return buffer.toString();
  }

  /// Converts accumulated validation results into a SARIF log.
  SarifLog _toSarif({String? toolVersion, String? rootDirectory}) {
    return SarifSerializer.toSarifLog(
      _results,
      toolVersion: toolVersion,
      checkTypes: RuleRegistry.allChecks,
      customRules: customRules,
      rootDirectory: rootDirectory,
    );
  }

  /// Serializes the accumulated validation results as a SARIF JSON string.
  String toSarifJson({bool pretty = true, String? toolVersion, String? rootDirectory}) {
    final SarifLog sarif = _toSarif(toolVersion: toolVersion, rootDirectory: rootDirectory);
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(sarif.toJson());
  }

  /// Serializes the accumulated validation results as a raw JSON array string.
  String toJsonOutput({bool pretty = true}) {
    final List<Map<String, Object?>> jsonList = _results.map((r) => r.toJson()).toList();
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(jsonList);
  }

  /// Re-validates every processed skill from disk after a `--fix` run that
  /// renamed at least one skill directory.
  ///
  /// Renaming a later skill can break a relative link in a sibling skill that
  /// was already validated. Re-validating once after all renames catches any
  /// new diagnostics, reports them, and updates [results] and [anyFailed].
  /// It runs only when at least one skill directory was renamed and more
  /// than one skill was validated.
  Future<void> revalidateAfterRenames() async {
    if (!_anySkillRenamed || _validatedSkills.length <= 1) {
      return;
    }
    _anySkillRenamed = false;
    _reporter.onRecheckAfterRenames();
    final baselinesToSave = <String, SkillsIgnores>{};
    // The renames changed files on disk, so an archive built earlier may be
    // stale.
    _pubArchiveLoader.clear();

    for (final _ValidatedSkill entry in _validatedSkills) {
      // A skill that --fix renamed is listed under its new directory, so a
      // missing directory means something outside this run removed it.
      if (!entry.skillDir.existsSync()) {
        continue;
      }
      final String skillName = p.basename(entry.skillDir.path);
      final List<IgnoreEntry> skillIgnores = entry.ignores.skills[skillName] ?? const [];
      final ValidationResult previous = _results[entry.resultIndex];
      final ValidationResult fresh = await entry.validator.validate(
        entry.skillDir,
        pubArchive: await _pubArchiveFor(entry.skillDir, entry.validator),
      );
      _applyIgnores(fresh, skillIgnores, entry.skillDir);
      _results[entry.resultIndex] = fresh;

      if (generateBaseline) {
        _updateBaselineForSkill(entry.ignores, fresh, skillName, entry.skillDir);
        baselinesToSave[entry.ignorePath] = entry.ignores;
      }

      if (!_sameDiagnostics(previous, fresh)) {
        _reporter.onSkillEvaluating(skillName);
        _reporter.onFixedSkillValidationComplete(fresh);
      }
    }
    // Every failure adds an invalid result, so a skill that a sibling's
    // rename made valid no longer fails the run.
    _anyFailed = _results.any((ValidationResult result) => !result.isValid);

    for (final MapEntry<String, SkillsIgnores> saveEntry in baselinesToSave.entries) {
      await _ignoreWriter.saveBaseline(saveEntry.key, saveEntry.value);
    }
  }

  static bool _sameDiagnostics(ValidationResult a, ValidationResult b) =>
      _sameStrings(a.errors, b.errors) && _sameStrings(a.warnings, b.warnings);

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Whether [session] refused a write or rename because it fell outside a
/// [WriteBoundary].
///
/// Internal to skills_lint: `package:skills_lint/skills_lint.dart` hides this
/// function.
bool writeRefusedInSession(ValidationSession session) => session._writeRefused;

class _ValidatedSkill {
  const _ValidatedSkill({
    required this.resultIndex,
    required this.skillDir,
    required this.validator,
    required this.ignores,
    required this.ignorePath,
  });

  final int resultIndex;
  final Directory skillDir;
  final Validator validator;
  final SkillsIgnores ignores;
  final String ignorePath;
}
