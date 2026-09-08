# Task 01 — Core Base Layer (`Result`, `Failure`, `BaseUseCase`, `BaseRepository`)

Depends on: Task 00.

## Prompt for Cursor

```
Inside lib/core/base/, create four files that form the foundation every
repository and usecase in this app will use. Never let raw exceptions reach
the presentation layer — everything funnels through Result<T>.

1. failure.dart
   - Abstract class `Failure` with `message` (String) and optional
     `statusCode` (int?).
   - Subclasses: ServerFailure, NoInternetFailure, TimeoutFailure,
     CacheFailure, UnauthorizedFailure (statusCode fixed to 401),
     UnknownFailure. Each has a sensible default message.

2. result.dart
   - A sealed class `Result<T>` with two variants: `Success<T>(T data)` and
     `ResultFailure<T>(Failure failure)`.
   - Factory constructors `Result.success(data)` / `Result.failure(failure)`.
   - Getters: `isSuccess`, `isFailure`, `dataOrNull`, `failureOrNull`.
   - A `when<R>({required success, required failure})` method using
     pattern matching (switch expression on the sealed class) so callers
     never need `is` checks.

3. base_usecase.dart
   - Abstract class `BaseUseCase<T, Params>` with a single method
     `Future<Result<T>> call(Params params)`.
   - A `NoParams` class (empty, const constructor) for usecases that need
     no input.

4. base_repository.dart
   - A mixin `BaseRepository` with one method:
     `Future<Result<T>> guard<T>(Future<T> Function() action)`.
   - It try/catches `action()`. On success wraps in `Result.success`.
   - On `DioException` (import package:dio/dio.dart), map `e.type` to the
     right Failure:
       connectionTimeout/sendTimeout/receiveTimeout -> TimeoutFailure
       connectionError -> NoInternetFailure
       badResponse -> read e.response?.statusCode; if 401 ->
         UnauthorizedFailure; else ServerFailure using
         e.response?.data['message'] if it's a Map, else a generic
         'Server error' message, with statusCode attached
       anything else -> UnknownFailure(e.message)
   - Any other caught exception -> UnknownFailure(e.toString()).

Every repository implementation elsewhere in this app must use
`with BaseRepository` and call `guard(() => someDataSourceCall())` instead
of writing its own try/catch.
```

## Acceptance criteria
- [ ] `Result<T>` is a sealed class (exhaustive switch, no default branch needed)
- [ ] `BaseRepository.guard` maps every `DioExceptionType` to a distinct `Failure` subtype
- [ ] No file in this task imports anything from `features/` — this layer is fully generic
- [ ] `flutter analyze` passes with zero errors on these four files
