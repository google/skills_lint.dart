#!/usr/bin/env bash
# Prints the open issues in the given repository that have no labels, oldest
# first, as JSON.
set -euo pipefail

repo="${1:?usage: list-open-issues.sh owner/repo}"
gh issue list --repo "$repo" --state open --limit 200 \
  --json number,title,createdAt,labels \
  --jq '[.[] | select(.labels | length == 0)] | sort_by(.createdAt)'
