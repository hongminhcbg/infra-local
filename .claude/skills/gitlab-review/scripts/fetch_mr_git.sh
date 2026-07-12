#!/usr/bin/env bash
# Git-only MR fetch — NO GitLab API key required.
# Uses GitLab's merge-request refs over the existing git remote (SSH / stored
# credential), so it keeps working if the company disables API tokens.
#
# Usage: fetch_mr_git.sh <mr_iid> [target_branch]
#   Prints: base, head, changed files (name-status), and the full diff.
#
# Limits vs the API helper: no MR title/description/author, and the target
# branch is guessed (origin's default) unless you pass it explicitly.
set -euo pipefail

iid="${1:?usage: fetch_mr_git.sh <mr_iid> [target_branch]}"
target="${2:-}"

# Fetch the MR head via GitLab's merge-request refs (works over SSH, no API).
git fetch --quiet origin "refs/merge-requests/${iid}/head:refs/mr/${iid}"

# Resolve the base/target branch: explicit arg, else origin's default, else main.
if [[ -z "$target" ]]; then
  if def="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    target="${def#refs/remotes/origin/}"
  else
    target="main"
  fi
fi
git fetch --quiet origin "$target"

base="origin/${target}"
head="refs/mr/${iid}"

echo "# MR !${iid}"
echo "# base: ${base}"
echo "# head: ${head} ($(git rev-parse --short "$head"))"
echo
echo "## authors (from git log — approximates MR author)"
git log --format='%an <%ae>' "${base}..${head}" | sort -u
echo
echo "## commits (title + intent from commit messages)"
git log --format='%h  %an  (%ad)%n    %s%n%b' --date=short "${base}..${head}"
echo
echo "## changed files"
git diff --name-status "${base}...${head}"
echo
echo "## diff"
git diff "${base}...${head}"
