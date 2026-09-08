import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/game_phase.dart';
import 'ar_play_game_strings.dart';
import 'en_play_game_strings.dart';

/// Language-specific Play copy. Use [forLanguage] or [playGameStringsProvider]
/// — never hardcode EN/AR.
abstract class PlayGameStrings {
  const PlayGameStrings();

  static const PlayGameStrings english = EnPlayGameStrings();
  static const PlayGameStrings arabic = ArPlayGameStrings();

  static PlayGameStrings forLanguage(String? languageCode) {
    return AppLanguage.isArabic(AppLanguage.normalize(languageCode))
        ? arabic
        : english;
  }

  String get waitingTitle;
  String get searchingPlayers;
  String get exitTheGame;
  String get areYouSureYouWantToGoOut;
  String get generalGame;
  String get playerVersusPlayer;
  String get iAmReady;
  String get playerReplaceHint;
  String get readyCountdownHint;
  String get pitchNumber;
  String get waitingForPlayer;

  /// Shown when JoinPrivateGame is answered with WrongGameCode.
  String get wrongGameCode;

  /// Shown in the private lobby when the other player leaves it.
  String get creatorTerminatedGame;
  String get roundPrefix;
  String get codeCopied;

  String shareGameMessage(String code);

  String get shareSheetTitle;
  String get pass;
  String get passAlert;
  String get report;
  String reportEmailSubject(String questionId);
  String get result;
  String get roundHeading;
  String get auctionRoundHeading;
  String get bellRoundHeading;
  String get comeBackRoundHeading;
  String get breakerRoundHeading;
  String get bidding;
  String get takeTheTurn;
  String get chooseTheNumberOfAnswers;
  String get choose;
  String get howManyAnswersPrefix;
  String get secondAuction;
  String get numberOfAttempts;
  String get strike;
  String get timeout;
  String get startTimer;
  /// Auction bidding overlay — the legacy `start_Increasing` resource.
  String get startIncreasing;

  String get skip;
  String get correctAnswer;
  String correctAnswerMessage(String playerName);
  String get wrongAnswer;
  /// Bell — the current device raced and won.
  String get youAreFastest;
  /// Bell — the opponent raced and won.
  String get opponentIsFastest;

  /// Turn overlay — the turn is this device's own.
  String get yourTurnNowLabel;

  /// Turn overlay — prefixes the named player whose turn it is.
  String get turnLabel;
  String get lobbyPlayTitle;
  String get lobbyPrivateTitle;
  String get wdykRoundTitle;
  String get auctionRoundTitle;
  String get bellRoundTitle;
  String get comeBackRoundTitle;
  String get breakerRoundTitle;
  String get finishRoundTitle;
  String get readyGameTitle;
  String get winTitle;
  String get winMessage;
  String get rewards;
  String get collectRewards;
  String get lossTitle;
  String get lossMessage;
  String get goodLuck;
  String get theGameIsOver;
  String get back;
  String get soundEffects;
  String get music;
  String get save;
  String get owned;
  String get buying;
  String get buy;
  String get areYouSureYouWantToBuy;
  String get confirm;
  String get interests;

  /// The turn overlay's text. This device's own turn names itself; the
  /// opponent's names them. The composition lives here so every round that
  /// raises the overlay reads identically, and so the newline is part of the
  /// copy rather than of any one caller.
  String turnOverlayText({required bool isMine, required String playerName}) {
    return isMine ? yourTurnNowLabel : '$turnLabel\n$playerName';
  }

  String howManyAnswersPrompt(String seconds) {
    return '$howManyAnswersPrefix $seconds $secondAuction';
  }

  String attemptsWarning(int count);

  String roundLabel(int stage) => '$roundPrefix $stage';

  String roundHeadingFor(GamePhase phase) {
    return switch (phase) {
      GamePhase.wdyk => roundHeading,
      GamePhase.auction => auctionRoundHeading,
      GamePhase.bell => bellRoundHeading,
      GamePhase.comeBack => comeBackRoundHeading,
      GamePhase.breaker => breakerRoundHeading,
      _ => '',
    };
  }

  String titleFor(GamePhase phase) {
    return switch (phase) {
      GamePhase.waiting => waitingTitle,
      GamePhase.lobbyPlay => lobbyPlayTitle,
      // Its own string, not the public lobby's. No phase currently reaches
      // the toolbar — GameControllerScreen's `isImmersive` enumerates all
      // nine, so `appBar` is always null and nothing here is rendered today.
      // That makes this mapping free to be correct rather than convenient:
      // if a phase ever stops being immersive, the private lobby already
      // names itself instead of silently reading "Play lobby".
      GamePhase.lobbyPrivate => lobbyPrivateTitle,
      GamePhase.wdyk => wdykRoundTitle,
      GamePhase.auction => auctionRoundTitle,
      GamePhase.bell => bellRoundTitle,
      GamePhase.comeBack => comeBackRoundTitle,
      GamePhase.breaker => breakerRoundTitle,
      GamePhase.finishRound => finishRoundTitle,
    };
  }
}

final playGameStringsProvider = Provider<PlayGameStrings>((ref) {
  return PlayGameStrings.forLanguage(ref.watch(appLanguageProvider));
});
