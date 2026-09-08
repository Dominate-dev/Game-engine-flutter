# Task 07 — Sample Feature (`chat_example`)

Depends on: Task 01–06 (uses every core layer). This is the ONLY screen in the app — do not create additional screens in this task.

## Prompt for Cursor

```
Build exactly one full-stack feature under lib/features/chat_example/ that
proves every core layer works together: REST history load + live SignalR
updates, rendered on a screen that extends BaseState.

DOMAIN LAYER
1. domain/entities/chat_message.dart
   - `ChatMessage extends Equatable` with final fields id (String),
     senderId (String), text (String), sentAt (DateTime). props = all four.

2. domain/repositories/chat_repository.dart
   - abstract class ChatRepository with
     `Future<Result<List<ChatMessage>>> getMessages();`

3. domain/usecases/get_messages_usecase.dart
   - `GetMessagesUseCase implements BaseUseCase<List<ChatMessage>, NoParams>`
     that just delegates to `repository.getMessages()`.

DATA LAYER
4. data/models/chat_message_model.dart
   - `ChatMessageModel extends ChatMessage` with `fromJson(Map)` factory.
   - ALSO add `factory ChatMessageModel.fromSignalRArgs(List<Object?>? args)`
     that extracts `args.first` as a Map (empty map if args is null/empty)
     and delegates to fromJson — this is how live SignalR event payloads
     get parsed the same way REST payloads do.
   - `toJson()` method.

5. data/datasources/chat_remote_datasource.dart
   - abstract class ChatRemoteDataSource with
     `Future<List<ChatMessageModel>> getMessages();`
   - Impl class taking an ApiClient, calling
     `apiClient.get<List<dynamic>>(ApiEndpoints.messages)` and mapping each
     item through `ChatMessageModel.fromJson`. This layer does NOT catch
     exceptions — let them propagate up to the repository's guard().

6. data/repositories/chat_repository_impl.dart
   - `ChatRepositoryImpl with BaseRepository implements ChatRepository`,
     `getMessages()` wraps the datasource call in `guard(() => ...)`.

PRESENTATION LAYER
7. presentation/providers/chat_providers.dart
   - Provider wiring: chatRemoteDataSourceProvider -> chatRepositoryProvider
     -> getMessagesUseCaseProvider (each reading the previous + apiClientProvider
     from core/di/providers.dart).
   - `ChatMessagesNotifier extends AsyncNotifier<List<ChatMessage>>`:
     - in `build()`: read signalRServiceProvider, call
       `signalR.subscribe(SignalREvents.onMessageReceived, _onMessageReceived)`
       (must be safe to call every time build() re-runs — subscribe() is
       already duplicate-safe per Task 04), register
       `ref.onDispose(() => signalR.unsubscribe(SignalREvents.onMessageReceived))`,
       then call the usecase and return its messages via `result.when(success: ..., failure: (f) => throw f)`
     - private `_onMessageReceived(List<Object?>? args)`: parse via
       `ChatMessageModel.fromSignalRArgs(args)`, append to
       `state.valueOrNull ?? []`, set `state = AsyncData([...current, incoming])`
   - `chatMessagesProvider = AsyncNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>`

8. presentation/pages/chat_page.dart
   - `ChatPage extends ConsumerStatefulWidget`, state class
     `_ChatPageState extends BaseState<ChatPage>` (implements `buildPage`,
     not `build`).
   - Watch `chatMessagesProvider` (AsyncValue) and
     `ref.watch(signalRStatusProvider).valueOrNull ?? SignalRStatus.idle`.
   - Scaffold with AppBar title 'Chat' and a small connection-status banner
     widget in the AppBar's `bottom:` (PreferredSize, height 24) that maps
     each SignalRStatus to a color+label: connected='Live'(green),
     connecting/reconnecting='Connecting…'/'Reconnecting…'(orange),
     disconnectedNoInternet='No internet'(red), disconnected='Disconnected'(red),
     failed='Connection failed'(red), idle='Idle'(grey).
   - Body: messagesAsync.when — data renders a ListView.builder of
     ListTiles (title=text, subtitle=senderId); loading shows a centered
     CircularProgressIndicator; error shows a centered error text AND, via
     addPostFrameCallback, calls `showAppSnackBar('Failed to load messages',
     type: ToastType.error)` to prove BaseState's snackbar helper works.
   - FloatingActionButton (refresh icon): on press, await
     `checkInternetConnection()`; if false, `showToast('No internet
     connection', type: ToastType.warning)` and return. Otherwise await
     `showConfirmDialog(title: 'Refresh', message: 'Reload chat history
     from server?')`; if confirmed, `ref.invalidate(chatMessagesProvider)`.

Do not build any navigation, routing, or second screen. This is the only
screen in the app by design.
```

## Acceptance criteria
- [ ] Leaving `ChatPage` (disposing `chatMessagesProvider`) unsubscribes the SignalR event — verify via `signalRService.isSubscribed('OnMessageReceived')` returning false afterward
- [ ] Tapping refresh with no internet shows a toast and does NOT call the usecase
- [ ] A message arriving over SignalR while history is still loading is not lost (appended once `build()` resolves)
- [ ] REST failures surface as a red error state AND a snackbar, not a silent blank screen
