# Review rubric

## Severity buckets

**Blocking** — must be resolved before merge:
- Incorrect business/domain logic: interest accrual, rounding, principal/fee math, double-entry
  balance, date/timezone boundaries, currency handling.
- Data integrity: unguarded writes, missing transaction boundaries, race conditions, partial updates.
- Security: injection, missing authz checks, leaked secrets, unsafe deserialization.
- Correctness: nil/error paths dropped, wrong variable in scope, off-by-one, broken caller contract.
- Missing test coverage for changed behavior that carries real risk.

**Nit** — optional, non-blocking:
- Naming, formatting, comment quality.
- Minor cleanups, dead code, small readability improvements.
- Preference-level structure with no behavioral impact.

Raise blocking findings; keep nits few and clearly labeled non-blocking. A reviewer who floods
an author with nits gets tuned out.

## Division of labor (AI vs. human)

Carry with the tool:
- Consistency with team conventions (from `AGENTS.md` / `CLAUDE.md`).
- Error handling / wrapping, nil checks, obvious races and dead code.
- Cross-file mechanics: "who calls this", "does this match the signature/type", "is there a test".

Leave to the human (flag as **needs your judgment**, do not assert):
- Whether the business rule itself is correct.
- Architecture and design fit; whether the change should exist at all.
- Domain edge cases the diff does not reveal.
- Trade-offs and tech-debt calls.

Rule of thumb: **AI for breadth and consistency, human for depth and money-correctness.**
"No mechanical issues found" is not sign-off on the business logic.

## Finding format

Each finding:
- `path:line` (use the MR's `new_path` and new-side line numbers)
- **Bucket**: blocking | nit
- **Summary**: one sentence
- **Why**: concrete failure scenario (inputs/state -> wrong result), not a vague concern
- **Confidence**: high | medium | low

Rank most-severe first. Prefer a concrete failure scenario over a general worry; if you cannot
describe how it breaks, it is probably a nit or not a finding.
