#!/usr/bin/env bash
# Fetch a GitLab merge request (or a sub-resource) as JSON.
#
# Usage:
#   fetch_mr.sh <mr_iid>            # MR metadata
#   fetch_mr.sh <mr_iid> changes   # diff + diff_refs (base/start/head sha)
#   fetch_mr.sh <mr_iid> <subpath> # any MR sub-resource (versions, discussions, ...)
#
# Auth:    reads PRIVATE-TOKEN from $GITLAB_TOKEN (never pass the token as an arg).
# Host:    $GITLAB_HOST, else derived from the `origin` remote, else gitlab.com.
# Project: $GITLAB_PROJECT, else derived from the `origin` remote.
set -euo pipefail

iid="${1:?usage: fetch_mr.sh <mr_iid> [subpath]}"
subpath="${2:-}"

: "${GITLAB_TOKEN:?GITLAB_TOKEN is not set in the environment}"

host="${GITLAB_HOST:-}"
project="${GITLAB_PROJECT:-}"

# Derive host + project path from the origin remote when not overridden.
if [[ -z "$host" || -z "$project" ]]; then
  url="$(git remote get-url origin 2>/dev/null || true)"
  stripped="${url%.git}"
  case "$stripped" in
    *@*:*)            # scp form: git@host:group/project
      h="${stripped#*@}"; h="${h%%:*}"
      p="${stripped#*:}"
      ;;
    http*://*)        # https form: https://host/group/project
      rest="${stripped#*://}"
      h="${rest%%/*}"
      p="${rest#*/}"
      ;;
    *)
      h=""; p=""
      ;;
  esac
  host="${host:-$h}"
  project="${project:-$p}"
fi

host="${host:-gitlab.com}"

if [[ -z "$project" ]]; then
  echo "fetch_mr.sh: could not derive GitLab project from origin; set GITLAB_PROJECT" >&2
  exit 1
fi

# URL-encode the slashes in the project path (group/project -> group%2Fproject).
enc_project="${project//\//%2F}"

api="https://${host}/api/v4/projects/${enc_project}/merge_requests/${iid}"
[[ -n "$subpath" ]] && api="${api}/${subpath}"

curl -sS --fail \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "$api"
