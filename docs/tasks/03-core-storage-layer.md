# Task 03 — Core Storage Layer (`SharedPrefsService`)

Depends on: Task 00.

## Prompt for Cursor

```
Inside lib/core/storage/, create shared_prefs_service.dart:

- Class `SharedPrefsService` wrapping a `SharedPreferences` instance,
  constructor takes the instance directly (no async work in the
  constructor).
- Static `Future<SharedPrefsService> init()` that calls
  `SharedPreferences.getInstance()` and returns a wrapped instance — this
  is the only async entry point, meant to be awaited once in main().
- Generic get/set methods for String, bool, and int (getString/setString,
  getBool/setBool, getInt/setInt), plus remove(key) and clear().
- Static const key constants: kAuthToken, kRefreshToken, kUserId (reserved
  for later — no auth flow exists yet, but keep the keys defined so future
  tasks don't have to touch this file again).
- Convenience getters/methods: `authToken` (String? getter),
  `saveAuthToken(String token)`, `clearAuthToken()`.

This service is intentionally the ONLY place SharedPreferences is touched
anywhere in the app — no feature should call SharedPreferences directly.
```

## Acceptance criteria
- [ ] `SharedPrefsService.init()` is the only async initialization path
- [ ] All key strings are defined as constants, never inline string literals elsewhere
- [ ] No other file in the project imports `shared_preferences` directly
