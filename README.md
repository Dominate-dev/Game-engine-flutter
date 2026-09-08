# game_engine — Flutter Module

A Flutter **module** (add-to-app) built with Clean Architecture, Riverpod, REST (Dio), and a global SignalR service. It embeds into existing native Android and iOS host apps.

The repository is a **pub workspace**: the root module plus two packages, `coreapp` (game-agnostic infrastructure) and `play_game` (the game plugin).

## Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Point the module at your backend with `--dart-define`. `ApiEndpoints.baseUrl` and `ApiEndpoints.signalRHubUrl` resolve from the environment at compile time and fall back to the test backend when unset:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://api.yourapp.com \
  --dart-define=SIGNALR_HUB_URL=https://api.yourapp.com/GameHub
```

Set **both** defines or neither — a half-configured build silently mixes environments. An add-to-app host does not use the `flutter run` / `flutter build` CLI and must pass the same values through the Flutter Gradle extension's `dartDefines`.

3. Run the debug launcher:

```bash
flutter run
```

The toolchain is pinned by `.android/local.properties`; if `flutter` is not on your `PATH`, invoke it by absolute path.

## Project structure

```
lib/                                       # Debug host — not the product surface
├── main.dart                              # Module entry: prefs, ProviderContainer, AppRoot
├── core/constants/debug_config.dart       # Debug-only login and ids
└── features/home/presentation/pages/      # HomeLauncherPage — the debug launcher

packages/coreapp/lib/                      # Game-agnostic infrastructure
├── audio/                                 # AudioService + provider
├── base/                                  # Result<T>, Failure, BaseRepository.guard()
├── connectivity/                          # ConnectionRecoveryController
├── constants/                             # ApiEndpoints, AppLanguage, colors, assets
├── di/                                    # sharedPrefsProvider, apiClientProvider
├── features/auth/                         # Login slice (data / domain / presentation)
├── l10n/                                  # AppStrings + EN / AR implementations
├── network/                               # ApiClient (Dio), JsonValue, ApiResponse, NetworkInfo
├── presentation/                          # BaseState, BaseDialog, BaseSheet, widget kit
├── security/                              # SecurityGenerator
├── signalr/                               # SignalRService + Riverpod providers
├── storage/                               # SharedPrefsService (only SharedPreferences user)
└── utils/                                 # AppLogger, AppLifecycleObserver

packages/play_game/lib/                    # Game plugin
├── constants/                             # PlayGameEndpoints, PlayGameHubEvents
├── domain/                                # GamePhase, GameType, GameSessionState, StatusGame
├── features/                              # games / profile / stickers vertical slices
├── l10n/                                  # PlayGameStrings + EN / AR
└── presentation/                          # GameController, hub bindings, screens, dialogs
```

`docs/` holds the engineering rules, task registry and assessments. `test/` holds every test, including tests for code in `packages/`, so one command runs them all.

## Layer flow

**UI → Provider/Notifier → UseCase → Repository (interface) → RepositoryImpl → DataSource → ApiClient / SignalRService**

Dependencies point inward only: presentation depends on domain; data implements domain contracts. `coreapp` never depends on a game plugin.

## SignalRService public API

| Method | Purpose |
|---|---|
| `connect({required url, accessTokenFactory?})` | Start (or resume) the hub connection. |
| `connectIfNeeded({...})` | Connect only when not already connected or connecting. |
| `reconnect()` | Force a reconnect using the stored hub url. |
| `checkConnectionStatus()` | Returns the tracked `SignalRStatus` (same value `signalRStatusProvider` emits). |
| `addEventListener(eventName, handler)` | Register an additional listener; returns a disposer. |
| `subscribe(eventName, handler)` | Register the primary event handler. Duplicate-safe — re-subscribing replaces the old handler. |
| `isSubscribed(eventName)` | Whether a primary handler is currently tracked. |
| `unsubscribe(eventName)` / `unsubscribeAll()` | Remove handlers. No-op if not subscribed. |
| `invoke(methodName, {args})` | Call a hub method. |
| `disconnect({manual = true})` | Stop the hub and cancel reconnect attempts. |

`SignalRService` is the only place a `HubConnection` may be constructed.

## Automatic reconnection

Do **not** re-implement reconnect logic in features. `SignalRService` handles:

- **Hub drop** — `onclose` plus a fallback reconnect timer
- **Built-in retry** — `withAutomaticReconnect`
- **Internet lost/regained** — via `networkInfoProvider`
- **App background/foreground** — `AppLifecycleObserver` in `packages/coreapp/lib/utils/`

## BaseState

Every screen extends `BaseState<T>` instead of `ConsumerState<T>`. Override `buildPage()`, never `build()`.

```dart
class _MyPageState extends BaseState<MyPage> {
  @override
  Widget buildPage(BuildContext context) {
    // ...
  }

  Future<void> _example() async {
    showToast('Saved', type: ToastType.success);
    showAppSnackBar('Something went wrong', type: ToastType.error);

    final ok = await showConfirmDialog(
      title: 'Delete',
      message: 'Are you sure?',
    );

    await showAppBottomSheet(child: MySheetContent());

    if (!await checkInternetConnection()) {
      showToast('No internet', type: ToastType.warning);
    }
  }
}
```

`BaseState` also provides `runApi()`, `showAppDialog()`, `showLoader()` / `hideLoader()`. Never call `ScaffoldMessenger` or `showDialog` directly.

## Adding a new feature

`SAMPLE_SCREEN.md` walks through a real slice end to end. In short:

1. Use `packages/play_game/lib/features/profile/` as the reference slice.
2. **Domain** — entity → abstract repository contract → usecase (pure Dart).
3. **Data** — model with `fromJson`, remote datasource (throws on error), repository impl using `guard()`.
4. **Presentation** — wire providers (datasource → repo → usecase), build a page extending `BaseState`.
5. Use `PlayGameEndpoints` for game URLs, `ApiEndpoints` for generic ones, and `PlayGameHubEvents` for hub event names — never hardcode strings.
6. Route hub events through `PlayGameHubBindings` rather than subscribing per screen.
7. Read JSON through `JsonValue`, never raw map access — payload keys arrive in mixed casing.

## Verification

```bash
flutter analyze   # baseline: 0 issues
flutter test      # see docs/TASKS.md for the current pass/fail baseline
```

Engineering rules, the task registry and testing strategy live in `docs/`. Read `docs/ENGINEERING_RULES.md` before modifying code.
