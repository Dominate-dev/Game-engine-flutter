# Task 09 — Documentation

Depends on: Task 00–08 (project must be fully built before writing docs about it).

## Prompt for Cursor

```
Generate two markdown files at the project root, describing the ACTUAL code
that now exists (don't invent anything not built in Tasks 00–08):

1. README.md
   - Setup instructions (flutter pub get, edit api_endpoints.dart).
   - The full lib/ folder tree with one-line descriptions per folder.
   - A one-line description of the layer flow:
     UI -> Provider/Notifier -> UseCase -> Repository (interface) ->
     RepositoryImpl -> DataSource -> ApiClient/SignalRService.
   - A table documenting the SignalRService public API (connect, checkConnectionStatus,
     subscribe, isSubscribed, unsubscribe, disconnect) with one line each on
     what each does and when to call it.
   - A short explanation of what reconnection is handled automatically
     (hub-level drop, internet lost/regained, app backgrounded/foregrounded)
     so nobody re-implements this elsewhere.
   - A short explanation of BaseState: extend it instead of ConsumerState,
     implement buildPage() not build(), and a code snippet showing
     showToast/showAppSnackBar/showConfirmDialog/showAppBottomSheet/
     checkInternetConnection usage.
   - A "adding a new feature" checklist: copy chat_example, define entity ->
     repo contract -> usecase in domain/, implement datasource + repo in
     data/, wire providers + build the page (extending BaseState) in
     presentation/.

2. SAMPLE_SCREEN.md
   - State clearly at the top: this project currently contains exactly ONE
     screen (ChatPage) and exists as a reference pattern — no navigation,
     auth, or other screens exist yet by design.
   - A table mapping each concern (base screen helpers, REST call, clean
     architecture flow, global SignalR handler, live connection status,
     internet check, Result/Failure handling) to the exact file that
     demonstrates it.
   - The buildPage() vs build() rule, with a minimal code skeleton.
   - A plain-language walkthrough of the data flow on ChatPage: REST loads
     history in build(), subscribe() attaches a live SignalR listener,
     incoming messages get appended to state, unsubscribe() happens
     automatically via ref.onDispose() when the provider is torn down.
   - A short section on the connection banner and what it reads
     (signalRStatusProvider).
   - A "adding your next screen" numbered list matching the one in
     README.md's checklist, phrased for someone about to copy chat_example.

Keep both files factual to the code that exists — no speculative sections
about features not yet built (no auth, no multi-screen navigation, no
push notifications, etc).
```

## Acceptance criteria
- [ ] Every file path mentioned in the docs actually exists in the project
- [ ] Neither file references screens, auth, or navigation that Tasks 00–08 didn't build
- [ ] A new contributor could read README.md alone and correctly add a second feature without asking questions
