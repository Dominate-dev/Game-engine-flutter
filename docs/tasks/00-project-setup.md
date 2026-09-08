# Task 00 — Project Setup

## Prompt for Cursor

```
Set up a new Flutter MODULE (not a regular app) named `flutter_clean_arch`
meant to be embedded into existing native Android and iOS apps via
add-to-app.

1. Scaffold it as a Flutter module:
   flutter create -t module --org com.yourcompany flutter_clean_arch

2. Replace pubspec.yaml dependencies with exactly this set:

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  dio: ^5.4.3
  pretty_dio_logger: ^1.3.1
  signalr_core: ^1.1.1
  connectivity_plus: ^6.0.3
  internet_connection_checker_plus: ^2.5.1
  shared_preferences: ^2.2.3
  fluttertoast: ^8.2.4
  freezed_annotation: ^2.4.1
  json_annotation: ^4.9.0
  equatable: ^2.0.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.9
  riverpod_generator: ^2.4.0
  freezed: ^2.5.2
  json_serializable: ^6.8.0

3. Create this empty folder structure under lib/ (no files yet, just
   directories, next tasks will fill them in):

lib/
├── core/
│   ├── base/
│   ├── constants/
│   ├── di/
│   ├── network/
│   ├── signalr/
│   ├── storage/
│   ├── presentation/
│   └── utils/
└── features/
    └── chat_example/
        ├── data/
        │   ├── datasources/
        │   ├── models/
        │   └── repositories/
        ├── domain/
        │   ├── entities/
        │   ├── repositories/
        │   └── usecases/
        └── presentation/
            ├── providers/
            └── pages/

4. Run `flutter pub get` and confirm it resolves cleanly.
```

## Acceptance criteria
- [ ] `flutter_clean_arch/` exists as a Flutter **module** (has `.android/` and `.ios/` hidden embedding folders, not a plain app)
- [ ] `pubspec.yaml` contains exactly the dependency set above
- [ ] Folder tree under `lib/` matches the structure above
- [ ] `flutter pub get` succeeds with no version conflicts
