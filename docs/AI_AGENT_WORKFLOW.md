# AI Agent Workflow

How Claude Code and any future AI agent must work in this repository.

Read [ENGINEERING_RULES.md](ENGINEERING_RULES.md) **before modifying code**.
Check [TASKS.md](TASKS.md) **before starting planned work**.

---

## The Loop

```
Inspect → Plan → Approval → Implement → Test → Analyze → Review → Report → STOP
```

Never skip Inspect. Never skip Report. Never skip STOP.

---

## 1. Inspect First

**Never implement before understanding the existing pattern.**

Inspect:

- the files you intend to change, in full — not just the lines you plan to edit;
- how the same problem is already solved elsewhere;
- callers of anything you plan to change or delete;
- existing tests covering the area;
- the current baseline in [TESTING_STRATEGY.md](TESTING_STRATEGY.md).

**This codebase contains deliberate decisions that look wrong until you read the
comment explaining them.** `skipNegotiation: true` in `signalr_service.dart` is
the clearest example — an in-code comment says the server rejects
`?access_token=` with close 1002. That comment is a *source*, not proof, and the
configuration is load-bearing until the premise is confirmed or refuted.

**Verify rather than assume.** During this project's assessments, several
plausible-sounding statements turned out to be wrong on inspection — a directory
believed empty held a hidden file; a directory believed deleted still existed;
a documented build command did not work in this environment. All were caught by
checking.

---

## 2. Never Guess

- **NEVER guess about the codebase, API behaviour, backend behaviour, business
  logic, or requirements.**
- If it is unclear, **inspect the code**.
- If it **cannot be determined from this repository, ask**.
- **Backend behaviour is never established here.** Attribute comment-sourced
  claims; do not restate them as fact.
- **Currently unresolved and off-limits for assumption:** WDYK and auction
  payload contracts, the close-1002 claim, release-build logging behaviour, and
  `signalr_core` maintenance state.
- **Resolved — safe to rely on:** identity semantics. The persisted login
  `user_id` and hub player ids share one namespace; hub player values can name
  either player; `PlayerLeft` arrives as `[playerId, gameId]`. Identity is
  decided by **positive matching against the persisted `user_id`** — never by
  *"not the opponent, therefore me"*.

Label every non-obvious claim:

| Label | Meaning |
|---|---|
| **VERIFIED** | Read in source, or confirmed by a command run against this checkout. Say which. |
| **INFERRED** | A reasonable reading of the code, not directly confirmed. |
| **EXTERNAL VERIFICATION REQUIRED** | Depends on the backend, a device, a release build, or an upstream package. |

---

## 3. Establish Scope

- **One approved task = one scope.**
- State explicitly what is **in** scope and what is **not**.
- Unrelated problems found along the way get **reported and recorded**, never
  fixed in passing. **E6**, **MA6** and **E5** were all found this way and left
  untouched.
- If the task turns out to require something outside the plan, **stop and report
  before proceeding**.

---

## 4. Report the Plan

Before writing code, produce:

- **Affected files** — exact paths, and what changes in each.
- **Current problem** — restated from evidence, not from the task title.
- **Proposed solution** — a concrete shape, with alternatives where they exist.
- **Dependencies** — on other tasks, on the backend, on a device.
- **Risks** — what could break, and what mitigates it.
- **Verification** — how you will know it worked, and what you will **not** be
  able to verify.

**Request approval** for anything with architectural, security, backend,
dependency, or destructive impact. Present the plan and **wait**. Do not begin
implementing while asking.

---

## 5. Implement Only the Approved Scope

- The approved scope, no more and no less.
- Follow existing patterns.
- No refactoring, renaming, reorganizing or tidying outside the task.
- **Never silently implement a better solution** — explain it and let the owner
  decide.

---

## 6. Test and Analyze

- Run the tests relevant to the change, then the full suite.
- Compare against the recorded baseline — **144 passing / 1 failing**, with
  `flutter analyze` reporting **0 issues**. The known
  failure is `widget_test.dart` (**T3**), pre-existing and not yours.
- Run `flutter analyze`. The baseline is **0 issues**, so any finding is one
  you introduced. Fix
  findings **you** introduced; do not fix others outside scope.
- **Never weaken, skip, delete or modify a test to make the suite pass.** A red
  test is evidence — **E6** was discovered exactly that way.
- **Do not add suppressions or weaken analyzer rules.** Prefer a legal access
  path, as A4 Option C did.

---

## 7. Review the Diff

Read the actual `git diff` before reporting. Check:

- **Unintended changes** — files you did not mean to touch, formatting churn.
- **Scope** — does the diff match the approved plan exactly?
- **Architecture consistency** — layer boundaries intact, no new `catch` in
  feature code, no direct `SharedPreferences` access, no hardcoded user-facing
  strings.
- **Security** — no payload logging, no ungated logging interceptor, no secrets.
- **Tests** — present, meaningful, not weakened.

**Prove a mechanical change is mechanical.** For A4 Option C, normalising the
rename back and confirming every diff line paired evenly is what established that
no logic changed. Do the equivalent for any bulk edit.

---

## 8. Report Exact Changes

Every report states:

1. **Files changed** — exact paths, and what changed in each.
2. **What changed** — the substance, not a restatement of the task title.
3. **Tests executed** — the commands actually run.
4. **Test results** — real numbers, compared to baseline.
5. **Analyzer result** — issue count, compared to baseline, with every remaining
   issue explained.
6. **Risks** — including residual risk the change surfaced but did not close.
7. **Remaining work** — anything outstanding, especially steps needing a device,
   a release build, or the backend.

**Distinguish verified fact from inference.** If a step was not run, say so and
mark it outstanding. **"It should work" is not a result.**

**Report your own errors plainly** and correct them — including errors in
analysis and documentation.

---

## 9. Stop

- **After the approved task, STOP.**
- Do not start another task automatically, even an obvious next one, even one
  already listed in [TASKS.md](TASKS.md).
- Finish with a report, not with more work.
- Wait for the next instruction.

---

## No Automatic Git Operations

- **NEVER commit.**
- **NEVER push.**
- **NEVER create a branch.**
- **NEVER reset, revert, checkout, stash, `rm`, `clean`, `restore`, amend,
  rebase or force-push.**
- Each requires an **explicit request for that specific action, at that time**.
  Approval of a task is not approval to commit it.
- **Read-only Git is expected** — `status`, `log`, `diff`, `show`.
- **Leave changes in the working tree** and report them. The owner decides what
  is committed.

---

## Agent Obligations

Agents **must**:

- read [ENGINEERING_RULES.md](ENGINEERING_RULES.md) before modifying code;
- check [TASKS.md](TASKS.md) before starting planned work, and use existing task
  IDs rather than inventing new ones;
- update [TASKS.md](TASKS.md) when a status changes;
- append to [CHANGELOG.md](CHANGELOG.md) after completed work;
- record newly discovered issues as tasks instead of fixing them opportunistically;
- keep documentation under `docs/`;
- keep comments minimal, avoid `///` unless explicitly requested, prefer a
  single-line `//`.

Agents **must never**:

- assume a file should be changed;
- delete code without checking for callers;
- silently change or expand scope;
- claim a task is complete without verification;
- mark a task `DONE` when only part of its verification was performed;
- fabricate a test result, an analyzer count, a command's output, a date, a
  commit, or a backend contract.
