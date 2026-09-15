// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// SARIF 2.1.0 document model.
///
/// A minimal document produced by `skills_lint --format=sarif`:
///
/// ```json
/// {
///   "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json",
///   "version": "2.1.0",
///   "runs": [
///     {
///       "tool": {
///         "driver": {
///           "name": "skills_lint",
///           "version": "0.5.2",
///           "informationUri": "https://github.com/google/skills_lint.dart",
///           "rules": [
///             {
///               "id": "description-too-long",
///               "shortDescription": { "text": "Validates frontmatter description length." },
///               "defaultConfiguration": { "level": "error" }
///             }
///           ]
///         }
///       },
///       "results": [
///         {
///           "ruleId": "description-too-long",
///           "ruleIndex": 0,
///           "level": "error",
///           "message": { "text": "Description exceeds 1024 characters." },
///           "locations": [
///             {
///               "physicalLocation": {
///                 "artifactLocation": { "uri": ".agents/skills/my-skill/SKILL.md" },
///                 "region": { "startLine": 3, "startColumn": 14 }
///               }
///             }
///           ]
///         }
///       ]
///     }
///   ]
/// }
/// ```
library;

export 'sarif_artifact_location.dart';
export 'sarif_driver.dart';
export 'sarif_location.dart';
export 'sarif_log.dart';
export 'sarif_message.dart';
export 'sarif_physical_location.dart';
export 'sarif_region.dart';
export 'sarif_reporting_configuration.dart';
export 'sarif_result.dart';
export 'sarif_rule.dart';
export 'sarif_run.dart';
export 'sarif_tool.dart';
