---
name: gitlab-review
description: Review a GitLab merge request locally using only git — no API key or token required. Use when the user wants to review a GitLab MR — e.g. "/gitlab-review 977", "review MR 981", or when they paste a GitLab merge-request URL. Fetches the MR through GitLab merge-request refs over the existing git remote, checks out the head in an isolated worktree, gathers cross-file context, and prints ranked findings. Reviews only — it never posts comments.
---

# GitLab MR Review (local, manual, no API key)

Review one GitLab merge request the way a tech lead would: fetch it with git, read it with full
repository context, and produce ranked findings. **No GitLab API token is required** — everything
comes through your existing git access to `origin` (SSH or stored credential). **This skill
reviews only — it never posts comments to GitLab.** Print the findings and stop.

## Inputs
- **MR reference**: an IID (e.g. `977`) or a full MR URL (extract the IID from
  `.../-/merge_requests/<iid>`).
- **Target branch** (optional): the MR's base branch. Defaults to the repo's default branch; ask
  the user if the MR targets a different branch.
- **Auth**: none. No API token or key of any kind, and no API calls — only git over the
  `origin` remote.

## Procedure

### 1. Fetch the MR (git only)
Run the helper — it uses GitLab's merge-request refs over the `origin` remote, no API key:
`bash .agent/skills/gitlab-review/scripts/fetch_mr_git.sh <iid> [target_branch]`

It fetches `refs/merge-requests/<iid>/head` into `refs/mr/<iid>` and prints:
- **authors** and **commit messages** (title + intent, from `git log`),
- the **changed files** (name-status), and
- the **diff** against the base branch.

If the fetch fails because the instance disabled merge-request refs, fall back to the MR's
**source branch by name**: `git fetch origin <source-branch>` and diff it against the base
(`git diff origin/<target>...origin/<source-branch>`). Ask the user for the source branch name.

### 2. Check out the MR head in an isolated worktree
Do NOT disturb the user's working tree. Add a detached worktree at the fetched ref:
`git worktree add --detach <scratch>/gl-mr-<iid> refs/mr/<iid>`
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
- No API tokens are used or needed — the skill authenticates only via your existing git remote.
- Confine Read/Grep to the repo and the MR worktree.
- Remove the worktree at the end, even if the review stops early.
- Read-only toward GitLab — this skill never posts.
