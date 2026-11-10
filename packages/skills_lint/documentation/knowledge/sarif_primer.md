# SARIF 2.1.0 Integration and Architecture Primer

## Overview

Static Analysis Results Interchange Format (SARIF) is an OASIS standard JSON format for output from static analysis tools. `skills_lint` implements SARIF 2.1.0 compliant output via the `--format=sarif` command-line option, enabling direct ingestion by GitHub Code Scanning, IDE extensions, and continuous integration dashboards.

## Schema Compliance

- **Canonical Schema URI**: `https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json`
- **Specification Version**: `2.1.0`
- **Tool Driver**:
  - `name`: `skills_lint`
  - `informationUri`: `https://github.com/google/skills_lint.dart`
  - `rules`: Full catalog of registered diagnostic rules with stable identifiers, descriptions, help URIs, and default configuration levels.

## Diagnostic Severity Mapping

`skills_lint` maps internal `AnalysisSeverity` levels to standard SARIF 2.1.0 result levels:

| `AnalysisSeverity` | SARIF Result Level | Ingestion Behavior |
|---|---|---|
| `AnalysisSeverity.error` | `error` | Blocks pull requests, reports failure in GitHub Code Scanning |
| `AnalysisSeverity.warning` | `warning` | Displays advisory notice in code review and scan tabs |
| `AnalysisSeverity.disabled` | `none` | Suppressed from SARIF run results unless explicitly queried |

## Source Location Coordinates

All SARIF locations in `skills_lint` use 1-based coordinates in accordance with SARIF 2.1.0 §3.30.2:
- `startLine`: 1-based line number (minimum value 1).
- `startColumn`: Optional 1-based character column offset.
- `endLine`: Optional 1-based ending line number.
- `endColumn`: Optional 1-based ending character column offset.
- Whole-File Diagnostics: Whole-file violations (such as missing skill files or directory structure failures) default to line 1.

## Configuration Notifications

Each run has one entry in `runs[].invocations[]`. Problems with `skills_lint.yaml` or an ignore file go in that entry's `toolConfigurationNotifications`, not in `results`, because SARIF 2.1.0 §3.20.22 keeps configuration problems apart from findings about the analyzed code. Each notification has:

- `level`: `error` when the problem stopped skills_lint from running, and `warning` when skills_lint ran without the problem entry, as with a malformed ignore entry or `--allow-misconfigured-keys`.
- `message.text`: the problem, without its location.
- `locations[].physicalLocation`: the configuration or ignore file, resolved against `%SRCROOT%` like the result locations. `region.startLine` and `region.startColumn` give the entry when skills_lint knows it. A notification about a configuration built in code, rather than read from a file, has no location.

`executionSuccessful` is `false` when any notification has level `error`, since §3.20.22 says such a notification means the run failed. Findings in `results` don't change it.

When a configuration error stops skills_lint, standard output still holds a SARIF log, with the notifications and no results. The errors also go to standard error.

GitHub Code Scanning accepts any valid SARIF 2.1.0 file, but its [list of supported properties](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning#supported-properties) leaves out `invocations`, so Code Scanning does not show these notifications. Read them from the uploaded file or from the job log.

## GitHub Code Scanning Integration

To ingest SARIF findings into GitHub Code Scanning, give the job `security-events: write` permission and add these steps:

```yaml
# skills_lint exits with code 1 when it finds violations. continue-on-error lets
# the upload step run before the final step fails the job.
- name: Run linter and generate SARIF
  id: lint
  continue-on-error: true
  run: dart run skills_lint --format=sarif > results.sarif

# Skip the upload if the lint step never ran, and on fork pull requests, which
# cannot be granted security-events: write.
- name: Upload SARIF to GitHub Code Scanning
  if: ${{ !cancelled() && steps.lint.conclusion != 'skipped' && (github.event_name != 'pull_request' || !github.event.pull_request.head.repo.fork) }}
  uses: github/codeql-action/upload-sarif@2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 # v4.38.2
  with:
    sarif_file: results.sarif
    category: skills_lint

- name: Fail the job when the linter found violations
  if: steps.lint.outcome != 'success'
  run: exit 1
```

> Note: Without the last step, `continue-on-error` makes the job pass even when the linter finds violations. This repository's [.github/workflows/code_scanning.yaml](../../../../.github/workflows/code_scanning.yaml) instead lets the lint step fail, uploads with `always()`, and reruns the linter in text format so the failing job's log shows the findings.
