# Homebrew formula

[`skills_lint.rb`](skills_lint.rb) installs the prebuilt `skills_lint`
executables that [`release.yaml`](../.github/workflows/release.yaml) attaches
to each GitHub Release. Homebrew reads only the `.rb` files in this directory,
so this file is not part of the tap's formulae.

The tap is `google/skills-lint`. Homebrew maps a tap name `user/repo` to the
repository `github.com/user/homebrew-repo`, and this repository has another
name, so users pass its URL to `brew tap`. The formula's version and checksums
are placeholders until the first release with executables. `brew install`
fails until then.

## What checks the formula

- [`repo_test/homebrew_formula_test.dart`](../packages/skills_lint/repo_test/homebrew_formula_test.dart)
  runs with the other repository checks. It fails when:
  - a release target that Homebrew can install has no `on_<os>` and
    `on_<arch>` block, or its block names another target's archive.
  - a `sha256` is missing, repeated, or a placeholder without a
    `# PLACEHOLDER` marker, or only some values are placeholders.
  - `version` is a prerelease. While the formula has placeholders, `version`
    must be the pubspec version without `-wip`. After that, it must have a
    `## <version>` heading in the CHANGELOG and must not be newer than the
    pubspec version.
  - `depends_on macos:` is outside `on_macos`, or names another macOS than
    `macosMinimumVersion` in `release/lib/src/macho.dart`.
  - the install matrix in `homebrew.yaml` differs from the release targets
    and their runners.
  - `packages/skills_lint/README.md` has the Homebrew install commands while
    the formula has placeholders.

  The release targets come from `releaseTargets` in
  `release/lib/src/archive.dart`, so a target added there fails this test
  until the formula and the workflow have it.
- [`homebrew.yaml`](../.github/workflows/homebrew.yaml) runs `brew style` and
  `brew audit --strict` on every pull request that changes `Formula/`,
  `release/` or the workflow, and weekly. Once the formula has no
  placeholders, it also installs the formula and runs its `test` block on
  each target. Its `Homebrew` job always reports a result, so it can be a
  required status check.
- [`CODEOWNERS`](../.github/CODEOWNERS) requests a review from `@reidbaker` on
  every change to this directory.

## Update the formula for a release

Do this for each release that has executables, until the `homebrew` job of
`release.yaml` (see below) does it.

1. Download the release's `SHA256SUMS` and archives, and check each archive:

   ```bash
   gh release download skills_lint-v<version> --repo google/skills_lint.dart --dir assets
   cd assets && sha256sum --check --strict SHA256SUMS
   for f in skills_lint-*.tar.gz; do
     gh attestation verify "$f" --repo google/skills_lint.dart \
       --signer-workflow google/skills_lint.dart/.github/workflows/release.yaml \
       --source-ref refs/heads/main
   done
   ```

2. In `skills_lint.rb`, set `version` to `<version>` and each `sha256` to the
   line for its archive in `SHA256SUMS`.
3. For the first release only:
   - Remove every `PLACEHOLDER` comment, including the header paragraph.
   - Add the [install section](#install-section-for-the-package-readme) to
     `packages/skills_lint/README.md`.
4. Run `dart test repo_test/homebrew_formula_test.dart` in
   `packages/skills_lint`, and open a pull request. The `Homebrew` workflow
   installs the formula on every target.

## Install section for the package README

The first release with executables adds this section to
`packages/skills_lint/README.md`, replacing the "Homebrew note" there. It
stays here until then, because `brew install` fails while the formula has
placeholders.

~~~markdown
### Homebrew — macOS 14+ and Linux (arm64, x64), no Dart required

The formula lives in this repository, in [`Formula/`](https://github.com/google/skills_lint.dart/tree/main/Formula).

```bash
brew tap google/skills-lint https://github.com/google/skills_lint.dart
brew install google/skills-lint/skills_lint
```

The `brew tap` command grants no trust. The fully qualified install command
trusts only this formula, not the whole tap. See
[Tap Trust](https://docs.brew.sh/Tap-Trust).

Homebrew has no prebuilt bottle for this formula, so it treats the install as
a build from source, though it only copies the release executable. On macOS
it refuses to install without the Xcode Command Line Tools. On a Linux
system whose glibc or libstdc++ is older than the ones Homebrew's CI uses,
such as Ubuntu 22.04, it also installs Homebrew's `gcc`.

Each release archive has a build provenance attestation. To check the archive
that Homebrew downloaded, run:

```bash
gh attestation verify "$(brew --cache google/skills-lint/skills_lint)" \
  --repo google/skills_lint.dart \
  --signer-workflow google/skills_lint.dart/.github/workflows/release.yaml
```
~~~

## Release automation

A `homebrew` job in `release.yaml` opens the pull request that updates the
formula. It merges after the release workflow and this formula. This section
is its specification.

- **When:** after the `publish` job, on runs that publish a release. It skips
  prereleases, because Homebrew installs the formula for every user.
- **Checks:** it downloads `SHA256SUMS` and the archives from the published
  release, checks them with `sha256sum --check --strict`, and runs
  `gh attestation verify --signer-workflow
  google/skills_lint.dart/.github/workflows/release.yaml --source-ref
  refs/heads/main` on each archive. If a check fails, it stops before it
  changes anything.
- **Change:** `dart run release homebrew-formula` in `release/` sets
  `version` and the `sha256` for each target that the formula installs from
  `SHA256SUMS`, and fails if `SHA256SUMS` lacks one of them. On the first
  release it also removes the `PLACEHOLDER` comments. A maintainer adds the
  README install section to that first pull request.
- **Output:** it pushes the branch `homebrew/skills_lint-v<version>` from
  `main` and opens a pull request. It never pushes to `main`. A maintainer
  reviews and merges it like any other change.
- **Token:** the job uses `GITHUB_TOKEN` with `contents: write`,
  `pull-requests: write` and `actions: write`. GitHub creates the
  `pull_request` runs of a pull request that `GITHUB_TOKEN` opens in an
  approval-required state, so the job also starts `homebrew.yaml` on the
  branch with `workflow_dispatch`, which GitHub always runs. That run reports
  the `Homebrew` check on the pull request's head commit. A maintainer selects
  **Approve workflows to run** on the pull request for the other workflows.
  - This needs the repository setting **Allow GitHub Actions to create and
    approve pull requests**. Without it, the job pushes the branch, fails to
    open the pull request, and writes a link to open it by hand in the job
    summary.
  - A GitHub App token would make the `pull_request` runs start without
    approval. It costs an App that an organization owner installs, its
    private key as a repository secret, and rotating that key. A personal
    access token costs the same secret and ties the job to one person's
    account. Neither is worth one click per release.

## Minimum macOS version

`depends_on macos: :sonoma` is the minimum macOS version of the release
executables, `macosMinimumVersion` in `release/lib/src/macho.dart`. Change
both together. Homebrew names macOS versions by major release only, so
`macosMinimumVersion` must be `<major>.0`. Add the symbol for a release that
the test does not know to `macosSymbolMajors` in
`repo_test/src/homebrew_formula.dart`.

## Platforms that the formula cannot install

Homebrew runs on macOS and Linux, and its formula DSL selects an archive by
`on_macos`/`on_linux` and `on_arm`/`on_intel` only. A release target for
another operating system, such as `windows-x64`, or another architecture,
such as `linux-riscv64`, has no formula block. The test ignores such targets,
so adding one to `release/lib/src/archive.dart` does not break it.
`scripts/install.sh` and pub.dev cover those platforms.

## Repository settings

These need a repository admin.

- **Require the `Homebrew` check on `main`.** Add a `required_status_checks`
  rule to the `main` ruleset. 15368 is the GitHub Actions app.

  ```bash
  gh api repos/google/skills_lint.dart/rulesets/21051370 \
    | jq '{name, target, enforcement, conditions, bypass_actors,
           rules: (.rules + [{type: "required_status_checks", parameters: {
             strict_required_status_checks_policy: false,
             do_not_enforce_on_create: false,
             required_status_checks: [{context: "Homebrew", integration_id: 15368}]}}])}' \
    | gh api -X PUT repos/google/skills_lint.dart/rulesets/21051370 --input -
  ```

- **Require `@reidbaker`'s approval for `Formula/`.** CODEOWNERS only requests
  the review. To require it, add a `required_reviewers` entry to the
  `pull_request` rule of the same ruleset. The reviewer must be a team with
  write access, so this needs a team that has `@reidbaker`; `<team-id>` is its
  ID from `gh api orgs/google/teams/<team-slug> --jq .id`.

  ```bash
  gh api repos/google/skills_lint.dart/rulesets/21051370 \
    | jq '{name, target, enforcement, conditions, bypass_actors,
           rules: [.rules[] | if .type == "pull_request" then
             .parameters.required_reviewers = [{minimum_approvals: 1,
               file_patterns: ["Formula/**"],
               reviewer: {id: <team-id>, type: "Team"}}] else . end]}' \
    | gh api -X PUT repos/google/skills_lint.dart/rulesets/21051370 --input -
  ```

  Turning on `require_code_owner_review` instead would also require
  `@reidbaker-agent`, the owner of every other file, to approve every other
  pull request, including its own, which GitHub does not allow.
- **Allow the release automation to open pull requests:**

  ```bash
  gh api -X PUT repos/google/skills_lint.dart/actions/permissions/workflow \
    -F can_approve_pull_request_reviews=true
  ```

  It fails with HTTP 409 if the organization does not allow the setting.

- **Check whether releases are immutable** (the formula does not depend on
  it): `gh api repos/google/skills_lint.dart/immutable-releases` returns 200
  if they are, and 404 if not.
