part of 'game_controller.dart';

/// Overlay durations from the T30 reference
/// (`docs/tasks/what-do-you-know-round-workflow.md`, section 5). These are
/// dialog lifetimes only — the match countdown is server-driven and unrelated.
const _wdykLongDialogMs = 2000; // intro, strike
const _wdykShortDialogMs = 1500; // turn, correct, timeout, reveal, skip

/// Round screen SignalR handlers.
/// Called when round screens receive hub events like ChangeTurn, Penalty, TimeStarted.
extension RoundScreenHandler on GameController {
  /// Round intro lottie + label — same as native `dialogStartRound`.
  Future<void> showRoundIntro(
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
    AudioService audio,
  ) async {
    // BUG-02: endGame deliberately leaves `phase` untouched, so a GameOver
    // landing within the same frame as entering a round would still pass
    // _isRoundPhase below — result is the authoritative "game is over"
    // signal and must suppress the intro so it cannot show over/behind the
    // result dialog.
    if (_s.result != null || !_isRoundPhase) {
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    final text = strings.roundHeadingFor(_s.phase);
    final lottie = _roundIntroLottie(_s.phase);
    if (text.isEmpty || lottie == null) {
      return;
    }
    final intro = RoundLottieDialog(
      text: text,
      timer: _wdykLongDialogMs,
      marginTop: 80,
      sound: AppSounds.startRound,
      lottie: lottie,
    );
    final phase = _s.phase;
    if (phase == GamePhase.wdyk ||
        phase == GamePhase.auction ||
        phase == GamePhase.bell) {
      // Through the chain, so an event arriving during the intro queues
      // behind it instead of stacking on top.
      _enqueueRoundDialog(phase, showDialog, intro);
      await _roundDialogChain;
    } else {
      await showDialog(barrierDismissible: false, child: intro);
    }
    await audio.startRunningMusic();
  }

  /// True unless the app is known to be away.
  ///
  /// A null lifecycle means no message has arrived yet — a freshly built tree
  /// is on screen, so it counts as foreground. So does a missing binding: a
  /// context with no widget layer has no off-screen dialog to prevent.
  bool get _isForeground {
    final AppLifecycleState? lifecycle;
    try {
      lifecycle = WidgetsBinding.instance.lifecycleState;
    } on FlutterError {
      return true;
    }
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  /// Whether the app is on screen right now.
  ///
  /// The round intro is scheduled from a post-frame callback, and a
  /// backgrounded app produces no frames — so the caller has to make that
  /// decision here, when the phase change is observed, rather than inside the
  /// callback, which would not run until the app was foreground again.
  bool get isAppForeground => _isForeground;

  /// Queues one round overlay behind the ones already running.
  ///
  /// [phase] is the round the overlay belongs to: it is re-checked at dequeue,
  /// so an overlay never lands on a screen the session has already left.
  ///
  /// Transient overlays are **dropped**, never replayed, while the app is away
  /// (T30 scenario N) — both when the event arrives and again when the dialog
  /// reaches the front of the queue, since the app can leave while it waits.
  ///
  /// The reference also specifies a wait after the turn overlay closes before
  /// its next step (1500ms WDYK / 4000ms Auction). That wait is intentionally
  /// not enforced here: it must not hold up whatever dialog is queued next, so
  /// every overlay is shown as soon as the one ahead of it closes.
  void _enqueueRoundDialog(
    GamePhase phase,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
    Widget child,
  ) {
    if (!_isForeground) {
      return;
    }
    final isIdle = _roundDialogsPending == 0;
    _roundDialogsPending++;
    Future<void> run() => _showRoundDialog(phase, showDialog, child)
        // A failed overlay must not poison the queue for the rest of the round.
        .catchError((Object error) {
          AppLogger.log('GameController — WDYK dialog skipped | $error');
        })
        .whenComplete(() => _roundDialogsPending--);
    // Nothing on screen: show it now. Deferring a lone overlay by a microtask
    // would only delay it — the queue exists to stop overlap, not to batch.
    _roundDialogChain = isIdle ? run() : _roundDialogChain.then((_) => run());
  }

  Future<void> _showRoundDialog(
    GamePhase phase,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
    Widget child,
  ) async {
    // Re-checked here, not only on arrival: the round can end or the app can
    // leave while this overlay waits its turn.
    if (_s.phase != phase || !_isForeground) {
      return;
    }
    await showDialog(barrierDismissible: false, child: child);
  }

  /// Whether [playerId] is this device's player. `null` when the id names
  /// neither seat, so the caller shows nothing rather than guessing a side.
  bool? _isMinePlayerId(String playerId) {
    if (playerId.isEmpty) {
      return null;
    }
    if (isCurrentUser(playerId)) {
      return true;
    }
    final opponent = _s.opponent;
    if (opponent != null && opponent.matchesHubUserId(playerId)) {
      return false;
    }
    return null;
  }

  Widget? _roundIntroLottie(GamePhase phase) {
    return switch (phase) {
      GamePhase.wdyk => const AppLottieView.wdyk(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      GamePhase.auction => const AppLottieView.auction(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      GamePhase.bell => const AppLottieView.bell(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      GamePhase.comeBack => const AppLottieView.comeBack(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      GamePhase.breaker => const AppLottieView.breaker(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      _ => null,
    };
  }

  /// Handle ChangeTurn event - shows dialog via callback if applicable.
  void onChangeTurn(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible}) showDialog,
  ) {
    if (_s.phase == GamePhase.auction) {
      onAuctionChangeTurn(data, showDialog);
      return;
    }
    if (_s.phase == GamePhase.bell) {
      onBellChangeTurn(data, showDialog);
      return;
    }
    if (_s.phase != GamePhase.wdyk) {
      return;
    }
    final playerId = (data?['playerId'] ?? data?['arg0'])?.toString() ?? '';
    final playerName = _playerNameFromData(data);
    if (playerName.isEmpty) {
      return;
    }
    // The overlay names the turn, not just the player: an id that reached
    // here already resolved to a seated player, so isCurrentUser decides
    // which of the two readings applies. The name source and the
    // empty-name-shows-nothing guard above are unchanged.
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.wdyk,
      showDialog,
      RoundLottieDialog(
        text: strings.turnOverlayText(
          isMine: isCurrentUser(playerId),
          playerName: playerName,
        ),
        timer: _wdykShortDialogMs,
        sound: AppSounds.startingGamerTurn,
        lottie: const AppLottieView.circularBlue(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// Handle Penalty event - shows dialog based on [TypePenalty].
  void onPenalty(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible}) showDialog,
  ) {
    if (_s.phase == GamePhase.auction) {
      onAuctionPenalty(data, showDialog);
      return;
    }
    if (_s.phase == GamePhase.bell) {
      onBellPenalty(data, showDialog);
      return;
    }
    if (_s.phase == GamePhase.comeBack || _s.phase == GamePhase.breaker) {
      onComebackPenalty(data, showDialog);
      return;
    }
    if (_s.phase != GamePhase.wdyk) {
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    final playerId = (data?['playerId'] ?? data?['arg0'])?.toString() ?? '';
    final type = TypePenalty.fromId(_penaltyTypeFrom(data));
    final isMe = isCurrentUser(playerId);
    final playerName = _playerNameForId(playerId);

    if (data != null && type == null) {
      AppLogger.log(
        'GameController — ${PlayGameHubEvents.penalty} type unresolved | '
        'data: $data',
      );
    }
    if (playerName.isEmpty || type == null) {
      return;
    }

    switch (type) {
      case TypePenalty.timeout:
        // My timeout is a strike (2000ms); watching the opponent time out is
        // the shorter red timeout overlay (1500ms).
        _enqueueRoundDialog(
          GamePhase.wdyk,
          showDialog,
          RoundLottieDialog(
            text: isMe ? strings.strike : strings.timeout,
            timer: isMe ? _wdykLongDialogMs : _wdykShortDialogMs,
            marginTop: isMe ? 75:0,
            // My own timeout is a strike; watching the opponent time out is
            // the spectator timeout overlay. Same isMe the copy and lottie
            // already branch on.
            sound: isMe ? AppSounds.getStrike : AppSounds.timeOver,
            lottie: isMe
                ? const AppLottieView.strike(
                    width: double.infinity,
                    height: 300,
                    fit: BoxFit.contain,
                  )
                : const AppLottieView.circularRed(
                    width: double.infinity,
                    height: 300,
                    fit: BoxFit.contain,
                  ),
          ),
        );
      case TypePenalty.wrongAnswer:
        if (isMe) {
          _enqueueRoundDialog(
            GamePhase.wdyk,
            showDialog,
            RoundLottieDialog(
              text: strings.strike,
              timer: _wdykLongDialogMs,
              marginTop: 80,
              sound: AppSounds.getStrike,
              lottie: const AppLottieView.strike(
                width: double.infinity,
                height: 300,
                fit: BoxFit.contain,
              ),
            ),
          );
        }
    }
  }

  /// Handle TimeStarted — timer lottie + start_time_t30.
  void onTimeStarted(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible}) showDialog,
  ) {
    if (_s.phase == GamePhase.auction) {
      onAuctionTimeStarted(showDialog);
      return;
    }
    if (_s.phase == GamePhase.bell) {
      onBellTimeStarted(showDialog);
      return;
    }
    if (_s.phase == GamePhase.comeBack || _s.phase == GamePhase.breaker) {
      onComebackTimeStarted(showDialog);
      return;
    }
    if (_s.phase != GamePhase.wdyk) {
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.wdyk,
      showDialog,
      RoundLottieDialog(
        timer: _wdykLongDialogMs,
        text: strings.startTimer,
        marginTop: 80,
        sound: AppSounds.startTime,
        lottie: const AppLottieView.timer(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// Handle PlayerPassed — the passer sees the skip lottie + pass_t30, the
  /// player watching sees the answer-reveal bar reading "Skip".
  void onPlayerPassed(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible}) showDialog,
  ) {
    if (_s.phase != GamePhase.wdyk) {
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    // Observed payload: [playerId, gameId], so arg0 is the passer.
    final playerId = _passedPlayerIdFrom(data);
    final isMine = _isMinePlayerId(playerId);
    if (isMine == null) {
      AppLogger.log(
        'GameController — ${PlayGameHubEvents.playerPassed} player unresolved '
        '| data: $data',
      );
      return;
    }
    _enqueueRoundDialog(
      GamePhase.wdyk,
      showDialog,
      isMine
          ? RoundLottieDialog(
              timer: _wdykShortDialogMs,
              text: strings.skip,
              sound: AppSounds.pass,
              lottie: const AppLottieView.circularGreen(
                width: double.infinity,
                height: 300,
                fit: BoxFit.contain,
              ),
            )
          : PlayerAnsweredDialog(
              answer: strings.skip,
              timer: _wdykShortDialogMs,
            ),
    );
  }

  /// Handle CorrectAnswer — green lottie + right_answer_t30.
  ///
  /// In WDYK the overlay belongs to the player who answered, so it is shown on
  /// that device only. The other round types are untouched and still show it
  /// on both, as before.
  void onCorrectAnswer(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible}) showDialog,
  ) {
    if (!_isRoundPhase) {
      return;
    }
    if (_s.phase == GamePhase.auction) {
      onAuctionCorrectAnswer(showDialog);
      return;
    }
    if (_s.phase == GamePhase.bell) {
      // Bell's own path: T30 does not branch on CorrectAnswer.playerId, so
      // this one is queued unconditionally — never the direct showDialog
      // fallback below, which would let it stack on top of another dialog.
      onBellCorrectAnswer(showDialog);
      return;
    }
    if (_s.phase == GamePhase.comeBack || _s.phase == GamePhase.breaker) {
      // Comeback's own path (also Breaker's, confirmed identical): unlike
      // WDYK, the answerer and the watching opponent see two different
      // dialogs — never the shared fallback below, which shows one
      // undifferentiated dialog to both.
      onComebackCorrectAnswer(data, showDialog);
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    final dialog = RoundLottieDialog(
      timer: _s.phase == GamePhase.wdyk
          ? _wdykShortDialogMs
          : _wdykLongDialogMs,
      text: strings.correctAnswer,
      sound: AppSounds.rightAnswer,
      lottie: const AppLottieView.circularGreen(
        width: double.infinity,
        height: 300,
        fit: BoxFit.contain,
      ),
    );
    if (_s.phase != GamePhase.wdyk) {
      showDialog(barrierDismissible: false, child: dialog);
      return;
    }
    final playerId = _correctAnswerPlayerIdFrom(data);
    final isMine = _isMinePlayerId(playerId);
    if (isMine == null) {
      AppLogger.log(
        'GameController — ${PlayGameHubEvents.correctAnswer} player unresolved '
        '| data: $data',
      );
      return;
    }
    if (!isMine) {
      return;
    }
    _enqueueRoundDialog(GamePhase.wdyk, showDialog, dialog);
  }

  bool get _isRoundPhase =>
      _s.phase == GamePhase.wdyk ||
      _s.phase == GamePhase.auction ||
      _s.phase == GamePhase.bell ||
      _s.phase == GamePhase.comeBack ||
      _s.phase == GamePhase.breaker;

  /// Handle PlayerAnswered — purple answer bar slides up (native).
  void onPlayerAnswered(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible}) showDialog,
  ) {
    if (_s.phase == GamePhase.auction) {
      onAuctionPlayerAnswered(data, showDialog);
      return;
    }
    if (_s.phase == GamePhase.bell) {
      onBellPlayerAnswered(data, showDialog);
      return;
    }
    if (_s.phase != GamePhase.wdyk) {
      return;
    }
    final text = _answeredTextFromData(data);
    if (text.isEmpty) {
      return;
    }
    _enqueueRoundDialog(
      GamePhase.wdyk,
      showDialog,
      PlayerAnsweredDialog(answer: text, timer: _wdykShortDialogMs),
    );
  }

  // Penalty arrives as [{playerId, type}, gameId] and mapFromArgs hands over
  // that first map, so the type is always a named field — no meaningful
  // position to fall back to. JsonValue tolerates PascalCase and a numeric
  // string; the previous `as int?` cast threw on either.
  int? _penaltyTypeFrom(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    return JsonValue.parseInt(JsonValue.field(data, 'type'));
  }

  String _answeredTextFromData(Map<String, dynamic>? data) {
    if (data == null) {
      return '';
    }
    // PlayerAnswered arrives as [{...}, gameId] with named fields; the
    // positional keys cover CorrectAnswer's [answerText, answerTextEn, ...].
    final ar = _answerTextField(data, 'answerText', 'arg0');
    final en = _answerTextField(data, 'answerTextEn', 'arg1');
    final isArabic = AppLanguage.isArabic(ref.read(appLanguageProvider));
    if (isArabic) {
      return ar.isNotEmpty ? ar : en;
    }
    return en.isNotEmpty ? en : ar;
  }

  String _answerTextField(
    Map<String, dynamic> data,
    String named,
    String positional,
  ) {
    final value = JsonValue.field(data, named) ?? data[positional];
    return value?.toString().trim() ?? '';
  }

  // PlayerPassed arrives as [playerId, gameId] — VERIFIED from a runtime log
  // recorded under W-ACTION: `PlayerPassed | args: [47, <gameId>]`.
  String _passedPlayerIdFrom(Map<String, dynamic>? data) =>
      _playerIdField(data, 'arg0');

  // CorrectAnswer is (text, textEn, playerId, gameId) per the owner-supplied
  // W-CONTRACT, and mapFromArgs keeps arg0..arg2, so the player is arg2 —
  // arg0 is the answer text, which is why it is not used here.
  String _correctAnswerPlayerIdFrom(Map<String, dynamic>? data) =>
      _playerIdField(data, 'arg2');

  String _playerIdField(Map<String, dynamic>? data, String positional) {
    if (data == null) {
      return '';
    }
    final named = JsonValue.field(data, 'playerId') ??
        JsonValue.field(data, 'userId');
    final value = named ?? data[positional];
    return value?.toString().trim() ?? '';
  }

  String _playerNameFromData(Map<String, dynamic>? data) {
    return _playerNameForId(
      (data?['playerId'] ?? data?['arg0'])?.toString() ?? '',
    );
  }

  // Positive matching only, via the S9 helpers. An id that names neither
  // player yields no name, so the caller shows nothing instead of blaming
  // the opponent.
  String _playerNameForId(String playerId) {
    if (playerId.isEmpty) {
      return '';
    }
    if (isCurrentUser(playerId)) {
      return _s.me?.playerName ?? '';
    }
    final opponent = _s.opponent;
    if (opponent != null && opponent.matchesHubUserId(playerId)) {
      return opponent.playerName;
    }
    return '';
  }
}
