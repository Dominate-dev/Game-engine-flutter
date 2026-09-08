import 'package:coreapp/coreapp.dart';

import '../../domain/entities/auction_game_metadata.dart';
import '../../domain/entities/created_game.dart';
import '../../domain/entities/current_question.dart';
import 'advs_model.dart';
import 'auction_game_metadata_model.dart';
import 'current_question_model.dart';
import 'game_json.dart';
import 'game_player_model.dart';

abstract final class CreatedGameModel {
  static CreatedGame fromJson(Map<String, dynamic> json) {
    return CreatedGame(
      id: GameJson.string(json, 'id'),
      status: GameJson.integer(json, 'status'),
      mode: GameJson.integer(json, 'mode'),
      currentTimerValue: GameJson.decimal(json, 'currentTimerValue'),
      groupId: GameJson.string(json, 'groupId'),
      players: GameJson.listOrNull(json, 'players', GamePlayerModel.fromJson),
      currentQuestion: _question(json),
      isPrivate: GameJson.boolean(json, 'isPrivate'),
      winnerId: GameJson.stringOrNull(json, 'winnerId'),
      showInterests: GameJson.boolean(json, 'showInterests'),
      multipleInterests: GameJson.boolean(json, 'multipleInterests'),
      type: GameJson.integer(json, 'type'),
      gameCode: GameJson.stringOrNull(json, 'gameCode'),
      auctionGameMetadata: _auction(json),
      currentTurn: GameJson.stringOrNull(json, 'currentTurn'),
      isTimerStarted: GameJson.booleanOrNull(json, 'isTimerStarted'),
      waitingToBeReadyTimerStart:
          GameJson.booleanOrNull(json, 'waitingToBeReadyTimerStart') ?? false,
      waitingToBeReadyTimerValue:
          GameJson.integerOrNull(json, 'waitingToBeReadyTimerValue'),
      beforeMatchAdv: AdvsModel.fromField(json, 'beforeMatchAdv'),
      tournmentGameName: GameJson.stringOrNull(json, 'tournmentGameName'),
      isAllInOne: GameJson.booleanOrNull(json, 'isAllInOne'),
    );
  }

  /// Overlays keys present in [json] onto [previous]. SignalR timer/turn
  /// events often send a partial [CreatedGame].
  static CreatedGame merge(
    CreatedGame? previous,
    Map<String, dynamic> json,
  ) {
    final incoming = fromJson(json);
    if (previous == null) {
      return incoming;
    }
    return previous.copyWith(
      id: JsonValue.hasField(json, 'id') ? incoming.id : null,
      status: JsonValue.hasField(json, 'status') ? incoming.status : null,
      mode: JsonValue.hasField(json, 'mode') ? incoming.mode : null,
      currentTimerValue: JsonValue.hasField(json, 'currentTimerValue') &&
              incoming.currentTimerValue >= 0
          ? incoming.currentTimerValue
          : null,
      groupId: JsonValue.hasField(json, 'groupId') ? incoming.groupId : null,
      players: JsonValue.hasField(json, 'players') ? incoming.players : null,
      currentQuestion: JsonValue.hasField(json, 'currentQuestion') ||
              JsonValue.hasField(json, 'answers')
          ? incoming.currentQuestion
          : null,
      isPrivate:
          JsonValue.hasField(json, 'isPrivate') ? incoming.isPrivate : null,
      winnerId: JsonValue.hasField(json, 'winnerId') ? incoming.winnerId : null,
      showInterests: JsonValue.hasField(json, 'showInterests')
          ? incoming.showInterests
          : null,
      multipleInterests: JsonValue.hasField(json, 'multipleInterests')
          ? incoming.multipleInterests
          : null,
      type: JsonValue.hasField(json, 'type') ? incoming.type : null,
      gameCode: JsonValue.hasField(json, 'gameCode') ? incoming.gameCode : null,
      auctionGameMetadata: JsonValue.hasField(json, 'auctionGameMetadata')
          ? incoming.auctionGameMetadata
          : null,
      // An explicit "" means "no player has the turn" (same as null), but the
      // parser collapses it to null and copyWith would preserve the old turn —
      // map present-but-empty to the '' no-turn sentinel so the clear applies.
      currentTurn: JsonValue.hasField(json, 'currentTurn')
          ? (incoming.currentTurn ?? '')
          : null,
      isTimerStarted: JsonValue.hasField(json, 'isTimerStarted')
          ? incoming.isTimerStarted
          : null,
      waitingToBeReadyTimerStart:
          JsonValue.hasField(json, 'waitingToBeReadyTimerStart')
              ? incoming.waitingToBeReadyTimerStart
              : null,
      waitingToBeReadyTimerValue:
          JsonValue.hasField(json, 'waitingToBeReadyTimerValue')
              ? incoming.waitingToBeReadyTimerValue
              : null,
      beforeMatchAdv: JsonValue.hasField(json, 'beforeMatchAdv')
          ? incoming.beforeMatchAdv
          : null,
      tournmentGameName: JsonValue.hasField(json, 'tournmentGameName')
          ? incoming.tournmentGameName
          : null,
      isAllInOne:
          JsonValue.hasField(json, 'isAllInOne') ? incoming.isAllInOne : null,
    );
  }

  static bool looksLikeCreatedGame(Map<String, dynamic> json) {
    if (looksLikeCurrentQuestion(json)) {
      return false;
    }
    return JsonValue.hasField(json, 'id') ||
        JsonValue.hasField(json, 'players') ||
        JsonValue.hasField(json, 'currentQuestion') ||
        JsonValue.hasField(json, 'currentTimerValue') ||
        JsonValue.hasField(json, 'currentTurn') ||
        JsonValue.hasField(json, 'status') ||
        JsonValue.hasField(json, 'answers');
  }

  /// [NextQuestion] sends the question map as arg0 (not a full [CreatedGame]).
  static bool looksLikeCurrentQuestion(Map<String, dynamic> json) {
    final hasQuestionShape = JsonValue.hasField(json, 'answers') ||
        JsonValue.hasField(json, 'questionNumber') ||
        JsonValue.hasField(json, 'maxCorrectAnswersCount');
    if (!hasQuestionShape) {
      return false;
    }
    return !JsonValue.hasField(json, 'players') &&
        !JsonValue.hasField(json, 'status') &&
        !JsonValue.hasField(json, 'groupId') &&
        !JsonValue.hasField(json, 'currentQuestion');
  }

  /// Parses [currentQuestion] nested, or a top-level question payload.
  static CurrentQuestion? questionFromHub(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final nested = GameJson.mapOrNull(data, 'currentQuestion');
    if (nested != null) {
      return CurrentQuestionModel.fromJson(nested);
    }
    if (looksLikeCurrentQuestion(data) || JsonValue.hasField(data, 'answers')) {
      return CurrentQuestionModel.fromJson(data);
    }
    return null;
  }

  static CurrentQuestion? _question(Map<String, dynamic> json) {
    return questionFromHub(json);
  }

  /// Question id for report email — from game state or latest hub payload.
  static int? reportQuestionId({
    CreatedGame? game,
    Map<String, dynamic>? data,
  }) {
    final fromGame = game?.currentQuestion?.id;
    if (fromGame != null && fromGame != 0) {
      return fromGame;
    }
    final fromData = questionFromHub(data)?.id;
    if (fromData != null && fromData != 0) {
      return fromData;
    }
    return null;
  }

  static AuctionGameMetadata? _auction(Map<String, dynamic> json) {
    final raw = GameJson.mapOrNull(json, 'auctionGameMetadata');
    if (raw == null) {
      return null;
    }
    return AuctionGameMetadataModel.fromJson(raw);
  }
}
