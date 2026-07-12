---
name: gitlab-review
description: Review a GitLab merge request locally with full repository context. Use when the user wants to review a GitLab MR — e.g. "/gitlab-review 977", "review MR 981", or when they paste a GitLab merge-request URL. Fetches the MR diff via the GitLab API, checks out the MR head in an isolated git worktree, gathers cross-file context, and prints ranked findings. Reviews only — it never posts comments.
---

# GitLab MR Review (local, manual)

Review one GitLab merge request the way a tech lead would: fetch it, read it with full
repository context, and produce ranked findings. **This skill reviews only — it never posts
comments to GitLab.** Print the findings and stop.

## Inputs
- **MR reference**: an IID (e.g. `977`) or a full MR URL. If given a URL, extract the project
  path and the IID from it (`.../<group>/<project>/-/merge_requests/<iid>`).
- **Project**: derived automatically from the `origin` remote. Override with `GITLAB_PROJECT`.
- **Host**: derived from `origin` (defaults to `gitlab.com`). Override with `GITLAB_HOST`.
- **Auth**: `GITLAB_TOKEN` must be set in the environment. Never print it, never write it to a
  file. If it is unset, stop and tell the user to `export GITLAB_TOKEN=...`.

## Procedure

### 1. Fetch the MR
Run the helper (it reads `GITLAB_TOKEN` and derives host/project from `origin`):
- Metadata: `bash .agent/skills/gitlab-review/scripts/fetch_mr.sh <iid>`
- Diff + refs: `bash .agent/skills/gitlab-review/scripts/fetch_mr.sh <iid> changes`

From the `changes` response, note `diff_refs.base_sha` / `start_sha` / `head_sha`, the
`changes[]` entries (each with `old_path`, `new_path`, `diff`, `new_file`, `deleted_file`,
`renamed_file`), and the source/target branches. From the metadata note title, description,
author, and target branch.

### 2. Check out the MR head in an isolated worktree
Do NOT disturb the user's working tree. Fetch the MR ref and add a detached worktree in the
scratch dir:
```
git fetch origin refs/merge-requests/<iid>/head
git worktree add --detach <scratch>/gl-mr-<iid> FETCH_HEAD
```
Use that worktree for all Read/Grep. **Always** remove it when finished (even if the review is
cut short): `git worktree remove --force <scratch>/gl-mr-<iid>`.

### 3. Load conventions
Read `AGENTS.md` and `CLAUDE.md` (and any rule files they link) so the review checks the team's
actual standards, not generic ones.

### 4. Gather context (agentic)
For each changed file: read the full file in the worktree, then pull only what the change needs
— callers, the relevant type/function definitions, and existing tests — via Grep/Read within
the worktree. Skip generated code, vendored dirs, and lockfiles. Cap yourself at roughly 15
tool calls per file; stop gathering once you can judge correctness. On a large MR, review
file-by-file carrying a short running summary so context does not overflow.

### 5. Produce findings
For any changed **Go** file (`.go`), also apply the Go-specific checklist in `reference/go.md`
(error wrapping with `%w`, goroutine leaks, context propagation/cancel, receiver types, nil
map/slice traps, `defer` in loops, the interface-nil trap, `time.Time` comparison, etc.).

Rank by severity and split into two buckets (see `reference/rubric.md`):
- **Blocking** — correctness, security, data-integrity, or money-math errors.
- **Nit** — style, naming, minor cleanups.
Each finding carries `file:line`, a one-line summary, a short rationale, and a confidence level.
Flag business-logic / domain-correctness concerns as **"needs your judgment"** — surface them,
do not assert them as settled.

### 6. Present and stop
Print a short header (files touched, overall risk, blocking/nit counts), then the findings with
**blocking first**. **Do not post anything to GitLab.** End by asking whether the user wants to
act on any finding.

## Guardrails
- Read `GITLAB_TOKEN` only from the environment; never echo, log, or persist it.
- Confine Read/Grep to the repo and the MR worktree.
- Remove the worktree at the end, even if the review stops early.
- This skill is read-only toward GitLab. Posting comments is a separate, explicit action.
