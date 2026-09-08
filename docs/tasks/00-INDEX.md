# Task Index — Flutter Clean Architecture Module (Riverpod + REST + SignalR)

Feed these files to Cursor **in order**, one at a time, in the same workspace.
Each task is a self-contained prompt: paste its full content into Cursor chat
(or use it as a `.cursor/rules`/context file) and let it generate the files
described. Don't skip ahead — later tasks assume earlier files exist.

| # | Task file | What it builds |
|---|---|---|
| 00 | `00-project-setup.md` | Flutter module scaffold + `pubspec.yaml` dependencies |
| 01 | `01-core-base-layer.md` | `Result<T>`, `Failure`, `BaseUseCase`, `BaseRepository` |
| 02 | `02-core-network-layer.md` | `ApiClient` (Dio) + `NetworkInfo` (real internet check) |
| 03 | `03-core-storage-layer.md` | `SharedPrefsService` |
| 04 | `04-core-signalr-handler.md` | Global SignalR service: connect, status, subscribe/unsubscribe, auto-reconnect |
| 05 | `05-core-presentation-layer.md` | `BaseState`, `BaseDialog`, `BaseSheet`, toast/snackbar interface |
| 06 | `06-di-and-constants.md` | Root Riverpod providers + API/SignalR endpoint constants |
| 07 | `07-sample-feature-chat.md` | One full sample screen wired through every layer above |
| 08 | `08-main-wiring.md` | `main.dart`: async init, lifecycle observer, SignalR connect at plugin start |
| 09 | `09-docs.md` | Generate `README.md` and `SAMPLE_SCREEN.md` |

## Ground rules to paste once at the start of your Cursor session

```
This is a Flutter MODULE (flutter create -t module), not a standalone app —
it will be embedded into existing native Android and iOS apps.

Non-negotiable architecture rules for every task in this series:
- Clean Architecture: presentation -> domain -> data, dependencies point inward only.
- State management: flutter_riverpod (Provider / AsyncNotifier / StreamProvider), no setState-based app state.
- Every repository implements guard()-style try/catch -> Result<T> (never throw into the UI layer).
- Only ONE sample screen exists until told otherwise — do not scaffold navigation,
  auth, or extra screens speculatively.
- SignalR connection logic lives in exactly one global service class — never
  instantiate HubConnection anywhere else in the codebase.
- Every screen extends a shared BaseState providing toast/snackbar/dialog/bottom
  sheet helpers — do not call ScaffoldMessenger/showDialog directly from a screen.
```

Work through tasks 00 → 09 in order. After each task, verify the files exist
and compile (`flutter analyze`) before moving to the next.
