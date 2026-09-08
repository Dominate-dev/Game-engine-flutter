# Sample Screen Reference

A practical walkthrough of one **real** vertical slice in this repository: the
public player profile. It is the smallest complete example of the architecture —
entity → repository contract → usecase → datasource → repository impl →
providers → a screen extending `BaseState`.

Every path below exists in the checkout. Use this slice as the template when
adding a screen.

## Concern → file mapping

| Concern | File |
|---|---|
| Base screen helpers (toast, snackbar, dialog, sheet, loader, internet check) | `packages/coreapp/lib/presentation/base_page.dart` |
| REST call | `packages/play_game/lib/features/profile/data/datasources/profile_remote_datasource.dart` |
| Clean architecture flow (entity → usecase → repo → datasource) | `packages/play_game/lib/features/profile/` (all layers) |
| Riverpod wiring for the slice | `packages/play_game/lib/features/profile/presentation/providers/profile_providers.dart` |
| The screen | `packages/play_game/lib/presentation/pages/playerProfile/player_profile_screen.dart` |
| Result / Failure handling | `packages/coreapp/lib/base/result.dart`, `packages/coreapp/lib/base/base_repository.dart` |
| Endpoint constants | `packages/play_game/lib/constants/play_game_endpoints.dart` |
| Tolerant JSON reads | `packages/coreapp/lib/network/json_value.dart` |
| Global SignalR handler | `packages/coreapp/lib/signalr/signalr_service.dart` |
| Hub event routing | `packages/play_game/lib/presentation/game_controller/play_game_hub_bindings.dart` |

## buildPage() vs build()

Screens extend `BaseState<T>` and implement `buildPage()`, not `build()`:

```dart
class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({super.key, this.playerId});

  final int? playerId;

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends BaseState<PlayerProfileScreen> {
  @override
  Widget buildPage(BuildContext context) {
    // ...
  }
}
```

`BaseState.build()` delegates to `buildPage()` and layers on the UI helpers,
the internet/hub listeners, and `runApi()`.

## The slice, layer by layer

**Domain — pure Dart, no Flutter imports.**

```dart
abstract class ProfileRepository {
  Future<Result<UserProfile>> getPublicProfile(int id);
}

class GetPublicProfileUseCase implements BaseUseCase<UserProfile, int> {
  const GetPublicProfileUseCase(this._repository);
  final ProfileRepository _repository;

  @override
  Future<Result<UserProfile>> call(int params) =>
      _repository.getPublicProfile(params);
}
```

**Data — the datasource throws; the repository converts.** Feature code
contains no `try`/`catch`; `guard()` is the single place exceptions become a
`Failure`.

```dart
class ProfileRepositoryImpl with BaseRepository implements ProfileRepository {
  const ProfileRepositoryImpl(this._remoteDataSource);
  final ProfileRemoteDataSource _remoteDataSource;

  @override
  Future<Result<UserProfile>> getPublicProfile(int id) =>
      guard(() => _remoteDataSource.getPublicProfile(id));
}
```

The datasource calls `ApiClient` with `PlayGameEndpoints.publicProfile(id)` —
never a raw URL string.

**Presentation — providers chain outward.**

```dart
final profileRemoteDataSourceProvider = Provider<ProfileRemoteDataSource>(...);
final profileRepositoryProvider       = Provider<ProfileRepository>(...);
final getPublicProfileUseCaseProvider = Provider<GetPublicProfileUseCase>(...);
final publicProfileProvider           = StateProvider<UserProfile?>((ref) => null);
```

## Screen data flow

`_loadProfile()` in `player_profile_screen.dart`:

1. Clears `publicProfileProvider` so a stale profile is never shown while
   loading.
2. Calls `runApi()` with the usecase. `runApi` checks connectivity, drives the
   loader, converts a thrown exception into a `Failure`, and shows the error
   itself — the screen writes no error handling.
3. On success, `onSuccess` writes the entity into `publicProfileProvider`.
4. `buildPage()` reads `ref.watch(publicProfileProvider)` and renders.

```dart
await runApi(
  () => ref.read(getPublicProfileUseCaseProvider)(id),
  loading: LoadingType.none,
  onSuccess: (profile) {
    ref.read(publicProfileProvider.notifier).state = profile;
  },
);
```

`loading: LoadingType.none` is deliberate here — the sheet renders its own
skeleton. Omit it to get the global loader instead.

An exception thrown *inside* `onSuccess` is logged and swallowed: the request
already succeeded, so a failing screen callback is a diagnostic, not a
user-facing API error.

## SignalR

This slice is REST-only. Hub events are **not** subscribed per screen — they
are bound once by `PlayGameHubBindings` and routed through `GameController`,
which screens read as state. Use `PlayGameHubEvents` constants; never hardcode
an event name.

## Adding your next screen

1. Copy `packages/play_game/lib/features/profile/` as the shape of a slice.
2. Define your entity, repository contract, and usecase in `domain/` — pure
   Dart only.
3. Implement the model, datasource, and repository in `data/`, using `guard()`
   in the repository and `JsonValue` for every JSON read.
4. Wire providers in `presentation/providers/`, then build the page extending
   `BaseState` and call it through `runApi()`.
5. Use `PlayGameEndpoints` / `ApiEndpoints` for URLs — no raw strings.
6. If the screen needs hub events, add the event name to `PlayGameHubEvents`
   and route it through `PlayGameHubBindings`, not a per-screen subscription.
7. Expose the screen through the `PlayGame` facade in
   `packages/play_game/lib/presentation/play_game_launcher.dart` if the host
   needs to open it.

Read `docs/ENGINEERING_RULES.md` before writing code, and add tests under
`test/` — one command runs everything, including tests for `packages/`.
