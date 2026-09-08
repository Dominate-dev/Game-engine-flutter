import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/data/models/game_over_result_model.dart';
import 'package:play_game/features/games/data/models/game_result_player_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

// GameOver result UI — WinDialog / LossDialog bound to the real
// GameOver.gameResultPlayers payload, instead of the hardcoded stub values
// they used to render unconditionally.
//
// CONFIRMED (real capture): GameResultPlayer.playerName /
// .profileImageUrl are empty on the real payload — `""`, not a real name —
// so display identity comes from the roster (GameSessionState.me /
// .opponent / .winnerPlayer), matching native's viewModel.userName /
// .playerName. gameResultPlayers stays the source for points/coins/xp.
//
// Confirmed real payload shape (given, not guessed):
//   winnerId = 29
//   { playerId: 47, points: 1, strikes: 2, correctAnswersCount: 2,
//     wrongAnswersCount: 0, winningCoins: 4, winningXP: 8, playerName: "",
//     profileImageUrl: "" }
//   { playerId: 29, points: 4, strikes: 0, correctAnswersCount: 2,
//     wrongAnswersCount: 0, winningCoins: 8, winningXP: 16, playerName: "",
//     profileImageUrl: "" }
// This device is player 47 — so this fixture is a LOSS: 29 (the opponent)
// won.

const _localId = '47';
const _opponentId = '29';

Map<String, dynamic> _resultPlayerJson({
  required String playerId,
  required int points,
  required int strikes,
  required int correctAnswersCount,
  required int wrongAnswersCount,
  required int winningCoins,
  required int winningXP,
  // Confirmed real-world default — the server sends these as empty
  // strings, not absent.
  String playerName = '',
  String profileImageUrl = '',
  String? profile,
}) =>
    {
      'playerId': playerId,
      'points': points,
      'strikes': strikes,
      'correctAnswersCount': correctAnswersCount,
      'wrongAnswersCount': wrongAnswersCount,
      'winningCoins': winningCoins,
      'winningXP': winningXP,
      'playerName': playerName,
      'profileImageUrl': profileImageUrl,
      if (profile != null) 'profile': profile,
    };

/// The exact confirmed payload shape — player 47 (me) lost to player 29.
/// playerName / profileImageUrl are the server's real empty strings.
Map<String, dynamic> _confirmedGameOverJson({
  List<Map<String, dynamic>>? gameResultPlayers,
}) =>
    {
      'gameId': 'g1',
      'winnerId': _opponentId,
      'gameResultPlayers': gameResultPlayers ??
          [
            _resultPlayerJson(
              playerId: _localId,
              points: 1,
              strikes: 2,
              correctAnswersCount: 2,
              wrongAnswersCount: 0,
              winningCoins: 4,
              winningXP: 8,
            ),
            _resultPlayerJson(
              playerId: _opponentId,
              points: 4,
              strikes: 0,
              correctAnswersCount: 2,
              wrongAnswersCount: 0,
              winningCoins: 8,
              winningXP: 16,
            ),
          ],
    };

void main() {
  group('GameResultPlayerModel.fromJson — data layer', () {
    test('parses every confirmed numeric/stat field', () {
      final player = GameResultPlayerModel.fromJson(
        _resultPlayerJson(
          playerId: '29',
          points: 4,
          strikes: 0,
          correctAnswersCount: 2,
          wrongAnswersCount: 0,
          winningCoins: 8,
          winningXP: 16,
        ),
      );

      expect(player.playerId, '29');
      expect(player.points, 4);
      expect(player.strikes, 0);
      expect(player.correctAnswersCount, 2);
      expect(player.wrongAnswersCount, 0);
      expect(player.winningCoins, 8);
      expect(player.winningXp, 16);
    });

    // CONFIRMED real behaviour: the server sends "" for playerName /
    // profileImageUrl, not a real name. GameJson.stringOrNull collapses an
    // empty string to null — this is exactly why display identity cannot
    // come from GameResultPlayer.
    test('an empty playerName / profileImageUrl parses to null, not ""', () {
      final player = GameResultPlayerModel.fromJson(
        _resultPlayerJson(
          playerId: _localId,
          points: 1,
          strikes: 2,
          correctAnswersCount: 2,
          wrongAnswersCount: 0,
          winningCoins: 4,
          winningXP: 8,
        ),
      );
      expect(player.playerName, isNull);
      expect(player.profileImageUrl, isNull);
    });

    test('missing optional fields parse safely, not crash', () {
      final player = GameResultPlayerModel.fromJson({
        'playerId': '47',
        'points': 1,
        'strikes': 2,
        'correctAnswersCount': 2,
        'wrongAnswersCount': 0,
        'winningCoins': 4,
        'winningXP': 8,
      });

      expect(player.playerId, '47');
      expect(player.points, 1);
      expect(player.winningCoins, 4);
      expect(player.winningXp, 8);
      expect(player.playerName, isNull);
      expect(player.profile, isNull);
      expect(player.profileImageUrl, isNull);
      expect(player.answersSpeed, 0);
    });

    test('an empty gameResultPlayers list parses to an empty list', () {
      final result = GameOverResultModel.fromJson(
        _confirmedGameOverJson(gameResultPlayers: const []),
      );
      expect(result.gameResultPlayers, isEmpty);
      expect(result.winnerId, _opponentId);
    });
  });

  group(
    'reducer — GameSessionState.myResult / .opponentResult / .winnerPlayer',
    () {
      late ProviderContainer container;
      late _FakeSignalRService signalR;
      late _FakeHubBindings bindings;

      Future<void> setUpContainer() async {
        SharedPreferences.setMockInitialValues({
          'user_id': _localId,
          'app_language': AppLanguage.english,
        });
        final prefs = await SharedPrefsService.init();
        signalR = _FakeSignalRService();
        bindings = _FakeHubBindings(signalR);
        container = ProviderContainer(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            signalRServiceProvider.overrideWithValue(signalR),
            playGameHubBindingsProvider.overrideWithValue(bindings),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(gameControllerProvider, (_, __) {});
        addTearDown(sub.close);
      }

      GameController notifier() =>
          container.read(gameControllerProvider.notifier);
      GameSessionState current() => container.read(gameControllerProvider);

      setUp(() async => setUpContainer());

      // The roster carries the real display names — GameResultPlayer's own
      // playerName is always empty on the real payload (see above), so this
      // is the only place a real name exists in this fixture.
      void startRound({List<Map<String, dynamic>>? players}) {
        notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
          'id': 'g1',
          'status': 3,
          'type': 1,
          'groupId': 'grp',
          'players': players ??
              [
                {
                  'id': _localId,
                  'playerName': 'Roster Me',
                  'profileImageUrl': 'https://cdn.example.com/roster-me.png',
                },
                {
                  'id': _opponentId,
                  'playerName': 'Roster Opponent',
                  'profileImageUrl': 'https://cdn.example.com/roster-opp.png',
                },
              ],
        });
      }

      test('winnerId correctly identifies the winner — I lose here', () {
        startRound();
        notifier().applySessionEvent(
          PlayGameHubEvents.gameOver,
          _confirmedGameOverJson(),
        );
        expect(current().result, GameResult.loss);
        expect(current().gameOver?.winnerId, _opponentId);
        expect(current().gameOver?.isWinner(_localId), isFalse);
        expect(current().gameOver?.isWinner(_opponentId), isTrue);
      });

      test(
        'winnerId correctly identifies the winner — the mirror case, I win',
        () {
          startRound();
          notifier().applySessionEvent(
            PlayGameHubEvents.gameOver,
            {
              'gameId': 'g1',
              'winnerId': _localId,
              'gameResultPlayers': [
                _resultPlayerJson(
                  playerId: _localId,
                  points: 4,
                  strikes: 0,
                  correctAnswersCount: 2,
                  wrongAnswersCount: 0,
                  winningCoins: 8,
                  winningXP: 16,
                ),
                _resultPlayerJson(
                  playerId: _opponentId,
                  points: 1,
                  strikes: 2,
                  correctAnswersCount: 2,
                  wrongAnswersCount: 0,
                  winningCoins: 4,
                  winningXP: 8,
                ),
              ],
            },
          );
          expect(current().result, GameResult.win);
          expect(current().myResult?.playerId, _localId);
          expect(current().myResult?.points, 4);
        },
      );

      // "Winner can be either current player or opponent" — winnerPlayer is
      // resolved from GameOver.winnerId against the roster, not assumed.
      test('winnerPlayer resolves to the opponent (roster) when they won',
          () {
        startRound();
        notifier().applySessionEvent(
          PlayGameHubEvents.gameOver,
          _confirmedGameOverJson(), // winnerId = opponent
        );
        final winner = current().winnerPlayer;
        expect(winner?.id, _opponentId);
        expect(
          winner?.playerName,
          'Roster Opponent',
          reason: 'from the roster, not GameResultPlayer.playerName (empty)',
        );
        expect(
          winner?.profileImageUrl,
          'https://cdn.example.com/roster-opp.png',
        );
      });

      test('winnerPlayer resolves to me (roster) when I won', () {
        startRound();
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': _localId,
          'gameResultPlayers': [
            _resultPlayerJson(
              playerId: _localId,
              points: 4,
              strikes: 0,
              correctAnswersCount: 2,
              wrongAnswersCount: 0,
              winningCoins: 8,
              winningXP: 16,
            ),
          ],
        });
        final winner = current().winnerPlayer;
        expect(winner?.id, _localId);
        expect(winner?.playerName, 'Roster Me');
      });

      test('winnerPlayer is null (not a crash) when winnerId is empty', () {
        startRound();
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': '',
          'gameResultPlayers': <dynamic>[],
        });
        expect(current().winnerPlayer, isNull);
      });

      test(
        'winnerPlayer is null (not a crash) when winnerId names neither '
        'seated player',
        () {
          startRound();
          notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
            'gameId': 'g1',
            'winnerId': '999999',
            'gameResultPlayers': <dynamic>[],
          });
          expect(current().winnerPlayer, isNull);
        },
      );

      test(
        "current user's GameResultPlayer (stats) is resolved by id, not "
        'array order',
        () {
          startRound();
          // Deliberately reversed vs. how startRound seats the roster, to
          // prove resolution does not assume ordering.
          notifier().applySessionEvent(
            PlayGameHubEvents.gameOver,
            _confirmedGameOverJson(
              gameResultPlayers: [
                _resultPlayerJson(
                  playerId: _opponentId,
                  points: 4,
                  strikes: 0,
                  correctAnswersCount: 2,
                  wrongAnswersCount: 0,
                  winningCoins: 8,
                  winningXP: 16,
                ),
                _resultPlayerJson(
                  playerId: _localId,
                  points: 1,
                  strikes: 2,
                  correctAnswersCount: 2,
                  wrongAnswersCount: 0,
                  winningCoins: 4,
                  winningXP: 8,
                ),
              ],
            ),
          );

          final me = current().myResult;
          expect(me?.playerId, _localId);
          expect(me?.points, 1);

          final opponent = current().opponentResult;
          expect(opponent?.playerId, _opponentId);
          expect(opponent?.points, 4);

          // Identity (name) still resolves from the roster regardless of
          // gameResultPlayers order.
          expect(current().me?.playerName, 'Roster Me');
          expect(current().opponent?.playerName, 'Roster Opponent');
        },
      );

      test(
        // Existing points/coins/XP mapping must be unaffected by this task.
        'the loser (me) gets my own result row — points/coins/xp still from '
        'gameResultPlayers',
        () {
          startRound();
          notifier().applySessionEvent(
            PlayGameHubEvents.gameOver,
            _confirmedGameOverJson(),
          );
          expect(current().result, GameResult.loss);
          final me = current().myResult!;
          expect(me.points, 1);
          expect(me.strikes, 2);
          expect(me.correctAnswersCount, 2);
          expect(me.wrongAnswersCount, 0);
          expect(me.winningCoins, 4);
          expect(me.winningXp, 8);

          final opponent = current().opponentResult!;
          expect(opponent.points, 4);
          expect(opponent.strikes, 0);
          expect(opponent.winningCoins, 8);
          expect(opponent.winningXp, 16);
        },
      );

      test('missing gameResultPlayers does not crash — both resolve to null',
          () {
        startRound();
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': _opponentId,
          'gameResultPlayers': <dynamic>[],
        });
        expect(current().result, GameResult.loss);
        expect(current().myResult, isNull);
        expect(current().opponentResult, isNull);
        // The roster still resolves the winner's name even with no stats.
        expect(current().winnerPlayer?.playerName, 'Roster Opponent');
      });

      test('a gameOver with no gameResultPlayers key at all does not crash',
          () {
        startRound();
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': _opponentId,
        });
        expect(current().result, GameResult.loss);
        expect(current().myResult, isNull);
        expect(current().opponentResult, isNull);
      });

      test('myResult / opponentResult / winnerPlayer survive a routine '
          'GameUpdated', () {
        startRound();
        notifier().applySessionEvent(
          PlayGameHubEvents.gameOver,
          _confirmedGameOverJson(),
        );
        expect(current().myResult?.points, 1);
        expect(current().opponentResult?.points, 4);
        expect(current().winnerPlayer?.playerName, 'Roster Opponent');

        notifier().applySessionEvent(PlayGameHubEvents.gameUpdated, {
          'id': 'g1',
          'status': 3,
          'type': 1,
          'groupId': 'grp',
          'players': [
            {'id': _localId, 'playerName': 'Roster Me'},
            {'id': _opponentId, 'playerName': 'Roster Opponent'},
          ],
        });

        expect(
          current().result,
          GameResult.loss,
          reason: 'already covered by the FinishRound work, re-asserted here',
        );
        expect(current().myResult?.points, 1);
        expect(current().opponentResult?.points, 4);
        expect(current().winnerPlayer?.playerName, 'Roster Opponent');
      });

      test(
        'myResult / opponentResult / winnerPlayer survive a stray '
        'GameRestore',
        () {
          startRound();
          notifier().applySessionEvent(
            PlayGameHubEvents.gameOver,
            _confirmedGameOverJson(),
          );

          notifier().applySessionEvent(PlayGameHubEvents.gameRestore, {
            'id': 'g1',
            'status': 3,
            'type': 1,
            'groupId': 'grp',
            'players': [
              {'id': _localId, 'playerName': 'Roster Me'},
              {'id': _opponentId, 'playerName': 'Roster Opponent'},
            ],
          });

          expect(current().result, GameResult.loss);
          expect(current().myResult?.points, 1);
          expect(current().opponentResult?.points, 4);
          expect(current().winnerPlayer?.playerName, 'Roster Opponent');
        },
      );
    },
  );

  group('widget — WinDialog / LossDialog render the real payload', () {
    late ProviderContainer container;

    Future<void> pumpDialog(
      WidgetTester tester,
      Widget dialog, {
      // MaterialApp.locale (main.dart) flips ambient Directionality to RTL
      // for Arabic; overriding it here directly simulates that without
      // needing to wire the language provider through to MaterialApp's own
      // locale resolution, which is unrelated to what these tests check.
      TextDirection ambientDirection = TextDirection.ltr,
    }) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Directionality(
              textDirection: ambientDirection,
              child: Scaffold(body: dialog),
            ),
          ),
        ),
      );
    }

    // Roster identity — this is where the real display name/avatar comes
    // from (GameSessionState.me / .opponent / .winnerPlayer).
    const meRoster = GamePlayer(
      id: _localId,
      playerName: 'Roster Me',
      penalty: 0,
      points: 0,
      isReady: true,
      makeupTryCount: 0,
      maxMakeupTryCount: 3,
      profileImageUrl: 'https://cdn.example.com/roster-me.png',
    );
    const opponentRoster = GamePlayer(
      id: _opponentId,
      playerName: 'Roster Opponent',
      penalty: 0,
      points: 0,
      isReady: true,
      makeupTryCount: 0,
      maxMakeupTryCount: 3,
      profileImageUrl: 'https://cdn.example.com/roster-opp.png',
    );

    // GameOver stats — playerName is deliberately empty here, matching the
    // real confirmed payload, to prove the dialogs no longer depend on it.
    const meResult = GameResultPlayer(
      playerId: _localId,
      points: 1,
      strikes: 2,
      correctAnswersCount: 2,
      wrongAnswersCount: 0,
      answersSpeed: 0,
      winningCoins: 4,
      winningXp: 8,
    );
    const opponentResult = GameResultPlayer(
      playerId: _opponentId,
      points: 4,
      strikes: 0,
      correctAnswersCount: 2,
      wrongAnswersCount: 0,
      answersSpeed: 0,
      winningCoins: 8,
      winningXp: 16,
    );

    testWidgets(
      'WinDialog shows the real winner name, from the roster, not the '
      'empty GameResultPlayer.playerName or the old hardcoded stub',
      (tester) async {
        await pumpDialog(
          tester,
          const WinDialog(
            winner: meRoster,
            me: meRoster,
            opponent: opponentRoster,
            meResult: meResult,
            opponentResult: opponentResult,
          ),
        );

        expect(find.text('Roster Me'), findsWidgets);
        expect(find.text('Roster Opponent'), findsWidgets);
        // Points/coins/xp still come from gameResultPlayers, unaffected.
        expect(find.text('1'), findsWidgets); // my points
        expect(find.text('4'), findsWidgets); // opponent's points
        expect(find.text('4'), findsWidgets); // my coins
        expect(find.text('8'), findsWidgets); // my xp

        expect(find.text('hassan hasanat'), findsNothing);
        expect(find.text('Mahmoud Salih'), findsNothing);
        expect(find.text('100'), findsNothing);
        expect(find.text('45'), findsNothing);
      },
    );

    testWidgets(
      "LossDialog shows the real winning opponent's name (roster) in the "
      'banner and both real names in the result rows',
      (tester) async {
        await pumpDialog(
          tester,
          const LossDialog(
            winner: opponentRoster,
            me: meRoster,
            opponent: opponentRoster,
            meResult: meResult,
            opponentResult: opponentResult,
          ),
        );

        expect(find.text('Roster Me'), findsWidgets);
        expect(find.text('Roster Opponent'), findsWidgets);
        expect(find.text('1'), findsWidgets); // my points
        expect(find.text('4'), findsWidgets); // opponent's (winner's) points
        expect(find.text('4'), findsWidgets); // my coins
        expect(find.text('8'), findsWidgets); // my xp

        expect(find.text('hassan hasanat'), findsNothing);
        expect(find.text('Mahmoud Salih'), findsNothing);
        expect(find.text('100'), findsNothing);
        expect(find.text('45'), findsNothing);
      },
    );

    testWidgets(
      'winner can be the current player (WinDialog) — the banner then '
      'shows my own roster name',
      (tester) async {
        await pumpDialog(
          tester,
          const WinDialog(winner: meRoster, me: meRoster),
        );
        expect(find.text('Roster Me'), findsWidgets);
      },
    );

    testWidgets(
      'winner can be the opponent (LossDialog) — the banner then shows '
      "the opponent's roster name",
      (tester) async {
        await pumpDialog(
          tester,
          const LossDialog(winner: opponentRoster, opponent: opponentRoster),
        );
        expect(find.text('Roster Opponent'), findsWidgets);
      },
    );

    testWidgets('WinDialog with no data at all does not crash',
        (tester) async {
      await pumpDialog(tester, const WinDialog());
      expect(find.byType(WinDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('LossDialog with no data at all does not crash',
        (tester) async {
      await pumpDialog(tester, const LossDialog());
      expect(find.byType(LossDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      "LossDialog with only my roster/result present (opponent's missing) "
      'does not crash and shows an empty opponent name rather than '
      'inventing one',
      (tester) async {
        await pumpDialog(
          tester,
          const LossDialog(me: meRoster, meResult: meResult),
        );
        expect(find.byType(LossDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.text('Roster Me'), findsWidgets);
      },
    );

    // A negative points value has nothing meaningful to show — it must
    // floor to 0, never render as a negative number.
    const meResultNegative = GameResultPlayer(
      playerId: _localId,
      points: -1,
      strikes: 0,
      correctAnswersCount: 0,
      wrongAnswersCount: 0,
      answersSpeed: 0,
      winningCoins: 0,
      winningXp: 0,
    );
    const opponentResultNegative = GameResultPlayer(
      playerId: _opponentId,
      points: -1,
      strikes: 0,
      correctAnswersCount: 0,
      wrongAnswersCount: 0,
      answersSpeed: 0,
      winningCoins: 0,
      winningXp: 0,
    );

    testWidgets('WinDialog floors negative points to 0 for both players',
        (tester) async {
      await pumpDialog(
        tester,
        const WinDialog(
          me: meRoster,
          opponent: opponentRoster,
          meResult: meResultNegative,
          opponentResult: opponentResultNegative,
        ),
      );
      expect(find.text('-1'), findsNothing);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('LossDialog floors negative points to 0 for both players',
        (tester) async {
      await pumpDialog(
        tester,
        const LossDialog(
          me: meRoster,
          opponent: opponentRoster,
          meResult: meResultNegative,
          opponentResult: opponentResultNegative,
        ),
      );
      expect(find.text('-1'), findsNothing);
      expect(find.text('0'), findsWidgets);
    });

    // Requirement 7 — the result row's name must always render on the
    // physical left of its own points, independent of ambient text
    // direction (MaterialApp.locale flips it to RTL for Arabic; the row
    // must not mirror). Distinct, otherwise-unused point values avoid any
    // collision with the coins/xp numbers rendered elsewhere on the card.
    const meResultLeftCheck = GameResultPlayer(
      playerId: _localId,
      points: 11,
      strikes: 0,
      correctAnswersCount: 0,
      wrongAnswersCount: 0,
      answersSpeed: 0,
      winningCoins: 0,
      winningXp: 0,
    );
    const opponentResultLeftCheck = GameResultPlayer(
      playerId: _opponentId,
      points: 22,
      strikes: 0,
      correctAnswersCount: 0,
      wrongAnswersCount: 0,
      answersSpeed: 0,
      winningCoins: 0,
      winningXp: 0,
    );

    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      testWidgets(
        'WinDialog result row: both names stay on the physical left of '
        'their own points ($direction)',
        (tester) async {
          await pumpDialog(
            tester,
            const WinDialog(
              me: meRoster,
              opponent: opponentRoster,
              meResult: meResultLeftCheck,
              opponentResult: opponentResultLeftCheck,
            ),
            ambientDirection: direction,
          );

          final myNameX = tester.getTopLeft(find.text('Roster Me')).dx;
          final myPointsX = tester.getTopLeft(find.text('11')).dx;
          expect(myNameX, lessThan(myPointsX));

          final opponentNameX =
              tester.getTopLeft(find.text('Roster Opponent')).dx;
          final opponentPointsX = tester.getTopLeft(find.text('22')).dx;
          expect(opponentNameX, lessThan(opponentPointsX));
        },
      );

      testWidgets(
        'LossDialog result row: both names stay on the physical left of '
        'their own points ($direction)',
        (tester) async {
          await pumpDialog(
            tester,
            const LossDialog(
              me: meRoster,
              opponent: opponentRoster,
              meResult: meResultLeftCheck,
              opponentResult: opponentResultLeftCheck,
            ),
            ambientDirection: direction,
          );

          final myNameX = tester.getTopLeft(find.text('Roster Me')).dx;
          final myPointsX = tester.getTopLeft(find.text('11')).dx;
          expect(myNameX, lessThan(myPointsX));

          final opponentNameX =
              tester.getTopLeft(find.text('Roster Opponent')).dx;
          final opponentPointsX = tester.getTopLeft(find.text('22')).dx;
          expect(opponentNameX, lessThan(opponentPointsX));
        },
      );
    }
  });
}

class _FakeSignalRService extends SignalRService {
  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) =>
      () {};

  @override
  void reattachEventHandlers() {}
}

class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(super.signalR);

  final _events = StreamController<GameHubEvent>.broadcast();

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}
