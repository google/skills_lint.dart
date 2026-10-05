#!/usr/bin/env bash
#
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
#
# install.sh — Install the skills_lint native binary.
#
# Usage (default repo + latest version):
#   curl -fsSL https://github.com/google/skills_lint.dart/releases/latest/download/install.sh | bash
#
# Pin a specific version or alternate repo:
#   curl -fsSL .../install.sh | REPO=other-org/other-repo VERSION=0.4.0-dev.1 bash
#
# Env vars:
#   REPO         GitHub owner/repo (default: google/skills_lint.dart).
#   VERSION      "latest" or a specific version like 0.4.0-dev.1 (default: latest).
#   INSTALL_DIR  Install destination (default: /usr/local/bin).

set -euo pipefail

REPO="${REPO:-google/skills_lint.dart}"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
BIN_NAME="skills_lint"

err()  { echo "install.sh: error: $*" >&2; exit 1; }
info() { echo "install.sh: $*"; }

# --- Detect platform ---------------------------------------------------------
# Names the machine as the release archives do, skills_lint-<os>-<arch>.tar.gz.
# Whether the release has an archive for it is checked against the release's
# SHA256SUMS below, so this script keeps no list of targets.
case "$(uname -s)" in
  Darwin) os="macos" ;;
  Linux)  os="linux" ;;
  *)      err "unsupported OS '$(uname -s)'." ;;
esac

case "$(uname -m)" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64)  arch="x64" ;;
  *)             err "unsupported architecture '$(uname -m)'." ;;
esac

target="${os}-${arch}"

# --- Required tools ---------------------------------------------------------
require() { command -v "$1" >/dev/null 2>&1 || err "required tool '$1' not found on PATH."; }
require curl
require tar
require awk

if command -v sha256sum >/dev/null 2>&1; then
  shasum_cmd() { sha256sum "$@"; }
elif command -v shasum >/dev/null 2>&1; then
  shasum_cmd() { shasum -a 256 "$@"; }
else
  err "required tools 'sha256sum' or 'shasum' not found on PATH. Install one to verify the binary."
fi

# --- Check the macOS version ------------------------------------------------
# The macOS binaries run on the macOS versions that the Dart SDK used for the
# release build supports. See "Targets" in RELEASING.md.
MIN_MACOS_VERSION=14
if [ "$os" = "macos" ]; then
  macos_version="$(sw_vers -productVersion 2>/dev/null || true)"
  macos_major="${macos_version%%.*}"
  case "$macos_major" in
    ''|*[!0-9]*) err "could not read the macOS version from 'sw_vers -productVersion' (got '${macos_version}')." ;;
  esac
  if [ "$macos_major" -lt "$MIN_MACOS_VERSION" ]; then
    err "${BIN_NAME} requires macOS ${MIN_MACOS_VERSION} or later (found ${macos_version})."
  fi
fi

# --- Resolve URLs ----------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
  base_url="https://github.com/${REPO}/releases/latest/download"
else
  tag="skills_lint-v${VERSION}"
  base_url="https://github.com/${REPO}/releases/download/${tag}"
fi
archive="${BIN_NAME}-${target}.tar.gz"
archive_url="${base_url}/${archive}"
sums_url="${base_url}/SHA256SUMS"

# --- Download into a tempdir, cleaned up on exit -----------------------------
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dart-skills-lint-install.XXXXXX")"
# Guard trap to prevent running rm -rf on empty/unbound tmpdir if trap triggers prematurely.
trap '[ -n "${tmpdir:-}" ] && rm -rf "$tmpdir"' EXIT INT TERM

info "downloading SHA256SUMS from ${REPO} (${VERSION})"
curl -fsSL --retry 3 -o "${tmpdir}/SHA256SUMS" "$sums_url" \
  || err "could not download ${sums_url}"

# --- Find the archive for this machine ---------------------------------------
# SHA256SUMS lists every archive of the release, so a release without an entry
# for this machine has no binary for it. Strip the optional leading '*' that
# `sha256sum -b` (binary mode) puts before the filename, so SHA256SUMS files
# from either text or binary mode work.
expected_sha="$(awk -v fname="$archive" '
  { sub(/^\*/, "", $2) }
  $2 == fname { print $1; exit }
' "${tmpdir}/SHA256SUMS")"
if [ -z "$expected_sha" ]; then
  # Each archive is <BIN_NAME>-<platform>.tar.gz; print the platforms.
  published="$(awk -v prefix="${BIN_NAME}-" '
    { sub(/^\*/, "", $2) }
    index($2, prefix) == 1 && sub(/\.tar\.gz$/, "", $2) {
      printf "%s%s", sep, substr($2, length(prefix) + 1); sep = ", "
    }
  ' "${tmpdir}/SHA256SUMS")"
  err "no published binary for platform '${target}' in ${REPO} (${VERSION}). Published platforms: ${published}."
fi

info "downloading ${archive}"
curl -fsSL --retry 3 -o "${tmpdir}/${archive}" "$archive_url" \
  || err "could not download ${archive_url}"

# --- Verify SHA256 ----------------------------------------------------------
actual_sha="$(shasum_cmd "${tmpdir}/${archive}" | awk '{print $1}')"
if [ "$expected_sha" != "$actual_sha" ]; then
  err "SHA256 mismatch for ${archive}. Expected ${expected_sha}, got ${actual_sha}."
fi
info "checksum verified"

# --- Extract ----------------------------------------------------------------
( cd "$tmpdir" && tar -xzf "$archive" )
extracted="${tmpdir}/${BIN_NAME}-${target}"
[ -x "$extracted" ] || err "extracted file ${extracted} not found or not executable."

# --- Install ----------------------------------------------------------------
install_path="${INSTALL_DIR}/${BIN_NAME}"

needs_sudo=0
if [ -d "$INSTALL_DIR" ]; then
  [ -w "$INSTALL_DIR" ] || needs_sudo=1
else
  parent="$(dirname "$INSTALL_DIR")"
  [ -d "$parent" ] && [ -w "$parent" ] || needs_sudo=1
fi

if [ "$needs_sudo" = "0" ]; then
  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$extracted" "$install_path"
elif command -v sudo >/dev/null 2>&1; then
  info "${INSTALL_DIR} is not writable; using sudo"
  sudo mkdir -p "$INSTALL_DIR"
  sudo install -m 0755 "$extracted" "$install_path"
else
  err "${INSTALL_DIR} is not writable and 'sudo' is not available. Set INSTALL_DIR to a writable path and re-run."
fi

# --- macOS Gatekeeper note (preview binaries are unsigned) ------------------
# Print BEFORE the launch check so users see the workaround even if Gatekeeper
# blocks the --help invocation below.
if [ "$os" = "macos" ]; then
  cat <<EOF
install.sh: note: this preview binary is not yet code-signed. If you see a
Gatekeeper warning ("cannot be opened because the developer cannot be
verified"), run:
    xattr -d com.apple.quarantine "${install_path}"
This removes the quarantine flag macOS sets on downloaded binaries.
EOF
fi

# --- Verify the installed binary launches -----------------------------------
# On macOS the launch check is best-effort because Gatekeeper can block
# unsigned downloaded binaries on first launch; treat the failure as
# informational so the install isn't marked as failed when the only thing
# wrong is the quarantine flag.
if "$install_path" --help >/dev/null 2>&1; then
  info "installed ${BIN_NAME} → ${install_path}"
  info "run '${BIN_NAME} --help' to get started"
elif [ "$os" = "macos" ]; then
  info "installed ${BIN_NAME} → ${install_path}"
  info "launch check failed — likely Gatekeeper. See the note above to clear quarantine, then run '${BIN_NAME} --help'."
else
  err "installed binary at ${install_path} failed to launch."
fi
