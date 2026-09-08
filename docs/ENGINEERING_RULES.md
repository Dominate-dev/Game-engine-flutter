# Engineering Rules

Rules every developer and AI agent must follow in this repository.

Read this **before** modifying any code. Process detail:
[AI_AGENT_WORKFLOW.md](AI_AGENT_WORKFLOW.md). Current state:
[PROJECT_ASSESSMENT.md](PROJECT_ASSESSMENT.md). Open work:
[TASKS.md](TASKS.md).

---

## 1. Inspect Before Modifying

1. **Inspect the actual code before changing it.** Read the file you intend to
   edit, and the callers of anything you intend to change.
2. **Find how the problem is already solved elsewhere** and follow that pattern.
3. **This codebase contains deliberate decisions that look wrong until you read
   the comment explaining them.** `skipNegotiation: true` in
   `signalr_service.dart` is the clearest example.
4. **Verify claims before repeating them.** Do not carry forward a statement
   from documentation or a previous session without re-checking it.

## 2. Never Guess

1. **NEVER guess about the codebase, API behaviour, backend behaviour, business
   logic, or requirements.**
2. If something is unclear, **inspect the code first**.
3. If it **cannot be determined from this repository, ask** — do not infer.
4. **Backend behaviour is never established by this repository.** A code comment
   describing what the server does is a source, not proof. Attribute it
   ("per the comment in `signalr_service.dart`…") rather than restating it as
   fact.
5. **Label every non-obvious claim** as VERIFIED, INFERRED, or
   EXTERNAL VERIFICATION REQUIRED — in reports, commit messages, and
   documentation alike.
6. **Currently blocked on external answers:** identity semantics (which id the
   hub sends where), auction payload contracts, the WebSocket close-1002 claim,
   release-build logging behaviour, and `signalr_core` maintenance state. Do not
   build on assumptions about any of them.

## 3. One Task at a Time

1. **One approved task = one scope.** Do not fix unrelated issues discovered
   during implementation.
2. Report unrelated findings separately and record them in
   [TASKS.md](TASKS.md).
3. **Approved scope only.** If the task turns out to require something outside
   the plan, stop and report before proceeding.
4. **After the approved task, STOP.** Do not start the next one automatically,
   even an obvious one, even one already listed in TASKS.md.
5. **NEVER silently implement a better solution than the one requested.**
   Explain the alternative and let the requester decide.
6. **NEVER refactor, rename, reorganize, or "tidy" anything outside the approved
   task** — including formatting, import order, dead-looking code, and lint
   findings you did not introduce.

## 4. Workflow

Every piece of work follows:

```
Inspect → Plan → Approval → Implement → Test → Analyze → Review → Report → STOP
```

Approval is required before implementing anything with architectural, security,
backend, dependency, or destructive impact.

## 5. Git

1. **No commit unless explicitly requested.**
2. **No push unless explicitly requested.**
3. **No branch creation unless explicitly requested.**
4. **No destructive Git operations without explicit approval** — `reset`,
   `revert`, `checkout`, `stash`, `rm`, `clean`, `restore`, amend, rebase,
   force-push.
5. **Read-only Git is expected and encouraged** — `status`, `log`, `diff`,
   `show`. You are required to review your own diff.
6. **Leave changes in the working tree** and report them. The owner decides what
   is committed.

## 6. Dependencies

1. **No dependency additions without approval** — direct, dev, transitive pins,
   or `dependency_overrides`, in any of the three pubspecs.
2. **Prefer existing utilities:** `JsonValue`, `AppLogger`,
   `SharedPrefsService`, `ApiResponseHandler`, `Result` / `Failure`, `AppUrl`,
   `AppShare`, `AppEmail`, `AudioService`, `postFrame`, and the `coreapp`
   widget kit.
3. **Removing a dependency is also a change** and needs the same approval.
4. Five codegen packages are declared but unused (**MA2**). Using one for the
   first time introduces a pattern and needs approval.

## 7. Tests

1. **NEVER weaken, disable, skip, delete, or modify a test to make the suite
   pass.** No `skip:`, no commenting out, no loosening a matcher.
2. **Fix the underlying problem** — unless the approved task explicitly changes
   the expected behaviour, in which case say so plainly and explain why the old
   expectation was wrong.
3. **Tests assert intended behaviour, not the current implementation.** A test
   written by reading the code and asserting whatever it does proves nothing.
4. **A red test is evidence, not an obstacle.**
5. **Characterization tests are the exception, and must be labelled.** When
   behaviour is unresolved (identity, E6), a test may record what the code does
   today — but it must be named `CHARACTERIZATION (unresolved)`, carry a comment
   stating it is not an endorsement, and must never be cited as proof that the
   behaviour is correct.
6. **Compare against the recorded baseline**, not against zero — see
   [TESTING_STRATEGY.md](TESTING_STRATEGY.md).

## 8. Analyzer

1. **Do not weaken analyzer rules or add broad suppressions.** `flutter analyze`
   is a quality gate and must stay trustworthy.
2. Prefer a **legal access path** over silencing a diagnostic — that is what A4
   Option C did.
3. **Fix findings you introduce.** Do not fix findings you did not introduce
   unless they are in the approved scope.
4. The current baseline is **0 issues**. Because it is clean, any finding in
   your run is one you introduced — fix it rather than reporting it as
   pre-existing.

## 9. Generated Files

1. **NEVER manually edit generated files** — `*.g.dart`, `*.freezed.dart`,
   `GeneratedPluginRegistrant`, and the generated `.android/` and `.ios/`
   scaffolding.
2. **If generated output must change, change the source and re-run the
   generator.** Never patch the artefact.
3. This repository currently contains **no** `*.g.dart` or `*.freezed.dart`
   files, so the Dart half is forward-looking; the `.android/` / `.ios/` half
   applies now.

## 10. Documentation

1. **Documentation lives under `docs/`.**
2. Update [TASKS.md](TASKS.md) when a task's status changes, and append to
   [CHANGELOG.md](CHANGELOG.md) after completed work.
3. Do not claim in documentation that something was fixed unless it was
   implemented **and** verified.

## 11. Comments

1. **Keep comments minimal.** Prefer self-explanatory code.
2. **Avoid DartDoc `///` unless explicitly requested.** Prefer a single-line
   `//` where a comment is genuinely needed.
3. **Do not add documentation blocks inside source files.**
4. This governs comments **you write**. The existing codebase uses `///`
   extensively, and several such comments record non-obvious *why*. Leave them
   alone — removing them is unrelated cleanup and is prohibited.

## 12. Architecture

1. **Preserve Clean Architecture** and the inward-only dependency direction.
2. **Do not change the architecture or introduce a new architectural pattern
   without explicit approval** — layering, DI, state management, navigation,
   error handling, package boundaries.
3. **Keep business logic out of the UI**, and UI concerns out of the state layer
   (**A5** is an open violation, not a precedent).
4. `coreapp` contains no game-specific logic. Game plugins depend on `coreapp`,
   never the reverse.
5. Game-specific REST paths belong in the plugin's own constants
   (`PlayGameEndpoints`), never in `coreapp`'s `ApiEndpoints`.

## 13. Networking, SignalR, Security

1. Data sources call `ApiClient` and throw; repositories wrap them in
   `BaseRepository.guard()`. **Feature code contains zero `try`/`catch` and that
   must be preserved.**
2. Unwrap responses through `ApiResponseHandler`; read JSON through `JsonValue`.
3. `SignalRService` is the only place a `HubConnection` may be constructed.
   **Do not reimplement reconnection in a feature.**
4. **Do not change SignalR transport or authentication behaviour** without
   backend confirmation.
5. **Never hardcode event or method names** — use `PlayGameHubEvents`.
6. **Never hardcode new secrets, and never expose sensitive data through logs.**
7. Read tokens through `SharedPrefsService`, never `SharedPreferences` directly.
   `PrefsKeys` names are shared with the native host — do not rename them.
8. **Never hardcode user-facing strings** — use `AppStrings` / `PlayGameStrings`
   with both EN and AR. (**MA6** is an open violation, not a precedent.)
