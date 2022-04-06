import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:games_services/games_services.dart' as games_services;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart' hide Level;
import 'package:provider/provider.dart';
import 'package:tictactoe/flavors.dart';
import 'package:tictactoe/src/achievements/player_progress.dart';
import 'package:tictactoe/src/achievements/score.dart';
import 'package:tictactoe/src/ads/ads_controller.dart';
import 'package:tictactoe/src/ai/ai_opponent.dart';
import 'package:tictactoe/src/audio/audio_controller.dart';
import 'package:tictactoe/src/audio/sounds.dart';
import 'package:tictactoe/src/game_internals/board_state.dart';
import 'package:tictactoe/src/level_selection/levels.dart';
import 'package:tictactoe/src/play_session/game_board.dart';
import 'package:tictactoe/src/play_session/hint_snackbar.dart';
import 'package:tictactoe/src/settings/custom_name_dialog.dart';
import 'package:tictactoe/src/settings/settings.dart';
import 'package:tictactoe/src/style/delayed_appear.dart';
import 'package:tictactoe/src/style/palette.dart';

class PlaySessionScreen extends StatefulWidget {
  final GameLevel level;

  const PlaySessionScreen(this.level, {Key? key}) : super(key: key);

  @override
  State<PlaySessionScreen> createState() => _PlaySessionScreenState();
}

class _PlaySessionScreenState extends State<PlaySessionScreen> {
  static final _log = Logger('PlaySessionScreen');

  static const _celebrationDuration = Duration(milliseconds: 2000);

  static const _preCelebrationDuration = Duration(milliseconds: 500);

  final StreamController<void> _resetHint = StreamController.broadcast();

  bool _duringCelebration = false;

  late DateTime _startOfPlay;

  late final AiOpponent opponent;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final state = BoardState.clean(
              widget.level.setting,
              opponent,
            );

            Future.delayed(const Duration(milliseconds: 500)).then((_) {
              if (!mounted) return;
              state.initialize();
            });

            state.playerWon.addListener(_playerWon);
            state.aiOpponentWon.addListener(_aiOpponentWon);

            return state;
          },
        ),
      ],
      child: IgnorePointer(
        ignoring: _duringCelebration,
        child: Scaffold(
          backgroundColor: palette.backgroundPlaySession,
          body: Stack(
            children: [
              Builder(builder: (context) {
                final textStyle = DefaultTextStyle.of(context).style.copyWith(
                      fontFamily: 'Permanent Marker',
                      fontSize: 24,
                      color: palette.redPen,
                    );
                final playerName = context.select(
                    (SettingsController settings) => settings.playerName);

                return _ResponsivePlaySessionScreen(
                  playerName: TextSpan(
                    text: playerName,
                    style: textStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => showCustomNameDialog(context),
                  ),
                  opponentName: TextSpan(
                    text: opponent.name,
                    style: textStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _log.warning('NOT IMPLEMENTED YET'),
                  ),
                  mainBoardArea: Center(
                    child: DelayedAppear(
                      ms: ScreenDelays.fourth,
                      delayStateCreation: true,
                      onDelayFinished: () {
                        final settings = context.read<SettingsController>();
                        if (!settings.muted && settings.soundsOn) {
                          final audioController =
                              context.read<AudioController>();
                          audioController.playSfx(SfxType.drawGrid);
                        }
                      },
                      child: Board(
                        key: Key('main board'),
                        setting: widget.level.setting,
                      ),
                    ),
                  ),
                  restartButtonArea: _RestartButton(
                    _resetHint.stream,
                    onTap: () {
                      final settings = context.read<SettingsController>();
                      if (!settings.muted && settings.soundsOn) {
                        final audioController = context.read<AudioController>();
                        audioController.playSfx(SfxType.buttonTap);
                      }

                      context.read<BoardState>().clearBoard();
                      _startOfPlay = DateTime.now();

                      Future.delayed(const Duration(milliseconds: 200))
                          .then((_) {
                        if (!mounted) return;
                        context.read<BoardState>().initialize();
                      });

                      Future.delayed(const Duration(milliseconds: 1000))
                          .then((_) {
                        if (!mounted) return;
                        showHintSnackbar(context);
                      });
                    },
                  ),
                  backButtonArea: DelayedAppear(
                    ms: ScreenDelays.first,
                    child: InkResponse(
                      onTap: () {
                        final settings = context.read<SettingsController>();
                        if (!settings.muted && settings.soundsOn) {
                          final audioController =
                              context.read<AudioController>();
                          audioController.playSfx(SfxType.buttonTap);
                        }

                        GoRouter.of(context).pop();
                      },
                      child: Tooltip(
                        message: 'Back',
                        child: Image.asset('assets/images/back.png'),
                      ),
                    ),
                  ),
                  settingsButtonArea: DelayedAppear(
                    ms: ScreenDelays.third,
                    child: InkResponse(
                      onTap: () {
                        final settings = context.read<SettingsController>();
                        if (!settings.muted && settings.soundsOn) {
                          final audioController =
                              context.read<AudioController>();
                          audioController.playSfx(SfxType.buttonTap);
                        }

                        GoRouter.of(context).push('/settings');
                      },
                      child: Tooltip(
                        message: 'Settings',
                        child: Image.asset('assets/images/settings.png'),
                      ),
                    ),
                  ),
                );
              }),
              SizedBox.expand(
                child: Visibility(
                  visible: _duringCelebration,
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/images/confetti.gif',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    opponent = widget.level.aiOpponentBuilder(widget.level.setting);
    _log.info('$opponent enters the fray');

    _startOfPlay = DateTime.now();

    final adsController = context.read<AdsController?>();
    adsController?.preloadAd(context);
  }

  void _aiOpponentWon() {
    // "Pop" the reset button to remind the player what to do next.
    _resetHint.add(null);
  }

  void _playerWon() async {
    final score = Score(
      widget.level.number,
      widget.level.setting,
      widget.level.aiDifficulty,
      DateTime.now().difference(_startOfPlay),
    );

    final playerProgress = context.read<PlayerProgress>();
    playerProgress.setLevelReached(widget.level.number);
    playerProgress.addScore(score);

    /// Let the player see the board just after winning for a bit.
    await Future.delayed(_preCelebrationDuration);
    if (!mounted) return;

    setState(() {
      _duringCelebration = true;
    });

    final settings = context.read<SettingsController>();
    if (!settings.muted && settings.soundsOn) {
      final audioController = context.read<AudioController>();
      audioController.playSfx(SfxType.congrats);
    }

    /// Send achievements.
    if (widget.level.achievementIdAndroid != null &&
        platformSupportsGameServices &&
        await games_services.GamesServices.isSignedIn) {
      games_services.GamesServices.unlock(
        achievement: games_services.Achievement(
          androidID: widget.level.achievementIdAndroid!,
          iOSID: widget.level.achievementIdIOS!,
        ),
      );
    }

    /// Give the player some time to see the celebration animation.
    await Future.delayed(_celebrationDuration);
    if (!mounted) return;

    if (platformSupportsGameServices) {
      if (await games_services.GamesServices.isSignedIn) {
        _log.info('Submitting $score to leaderboard.');
        games_services.GamesServices.submitScore(
            score: games_services.Score(
          iOSLeaderboardID: "tictactoe.highest_score",
          androidLeaderboardID: "CgkIgZ29mawJEAIQAQ",
          value: score.score,
        ));
      }
    }
    if (!mounted) return;

    GoRouter.of(context).go('/play/won', extra: {'score': score});
  }
}

class _RestartButton extends StatefulWidget {
  final Stream<void> resetHint;

  final VoidCallback onTap;

  const _RestartButton(this.resetHint, {required this.onTap, Key? key})
      : super(key: key);

  @override
  State<_RestartButton> createState() => _RestartButtonState();
}

class _RestartButtonState extends State<_RestartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1500),
    vsync: this,
  );

  StreamSubscription? _subscription;

  static final TweenSequence<double> _bump = TweenSequence([
    // A bit of delay.
    TweenSequenceItem(tween: Tween(begin: 1, end: 1), weight: 10),
    // Enlarge.
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 1),
    // Slowly go back to beginning.
    TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 3),
  ]);

  @override
  void initState() {
    super.initState();
    _subscription = widget.resetHint.listen(_handleResetHint);
  }

  @override
  void didUpdateWidget(covariant _RestartButton oldWidget) {
    _subscription?.cancel();
    _subscription = widget.resetHint.listen(_handleResetHint);
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DelayedAppear(
      ms: ScreenDelays.fourth,
      child: InkResponse(
        onTap: widget.onTap,
        child: Column(
          children: [
            ScaleTransition(
              scale: _bump.animate(_controller),
              child: Image.asset('assets/images/restart.png'),
            ),
            Text(
              'Restart',
              style: TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleResetHint(void _) {
    _controller.forward(from: 0);
  }
}

class _ResponsivePlaySessionScreen extends StatelessWidget {
  /// This is the "hero" of the screen. It's more or less square, and will
  /// be placed in the visual "center" of the screen.
  final Widget mainBoardArea;

  final Widget backButtonArea;

  final Widget settingsButtonArea;

  final Widget restartButtonArea;

  final TextSpan playerName;

  final TextSpan opponentName;

  /// How much bigger should the [mainBoardArea] be compared to the other
  /// elements.
  final double mainAreaProminence;

  const _ResponsivePlaySessionScreen({
    required this.mainBoardArea,
    required this.backButtonArea,
    required this.settingsButtonArea,
    required this.restartButtonArea,
    required this.playerName,
    required this.opponentName,
    this.mainAreaProminence = 0.8,
    Key? key,
  }) : super(key: key);

  Widget _buildVersusText(BuildContext context, TextAlign textAlign) {
    String versusText;
    switch (textAlign) {
      case TextAlign.start:
      case TextAlign.left:
      case TextAlign.right:
      case TextAlign.end:
        versusText = '\nversus\n';
        break;
      case TextAlign.center:
      case TextAlign.justify:
        versusText = ' versus ';
        break;
    }

    return DelayedAppear(
      ms: ScreenDelays.second,
      child: RichText(
          textAlign: textAlign,
          text: TextSpan(
            children: [
              playerName,
              TextSpan(
                text: versusText,
                style: DefaultTextStyle.of(context)
                    .style
                    .copyWith(fontFamily: 'Permanent Marker', fontSize: 18),
              ),
              opponentName,
            ],
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // This widget wants to fill the whole screen.
        final size = constraints.biggest;
        final padding = EdgeInsets.all(size.shortestSide / 30);

        if (size.height >= size.width) {
          // "Portrait" / "mobile" mode.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: padding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 45,
                        child: backButtonArea,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 15,
                            right: 15,
                            top: 5,
                          ),
                          child: _buildVersusText(context, TextAlign.center),
                        ),
                      ),
                      SizedBox(
                        width: 45,
                        child: settingsButtonArea,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: (mainAreaProminence * 100).round(),
                child: SafeArea(
                  top: false,
                  bottom: false,
                  minimum: padding,
                  child: mainBoardArea,
                ),
              ),
              SafeArea(
                top: false,
                maintainBottomViewPadding: true,
                child: Padding(
                  padding: padding,
                  child: restartButtonArea,
                ),
              ),
            ],
          );
        } else {
          // "Landscape" / "tablet" mode.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: SafeArea(
                  right: false,
                  maintainBottomViewPadding: true,
                  child: Padding(
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        backButtonArea,
                        Expanded(
                          child: _buildVersusText(context, TextAlign.start),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 7,
                child: SafeArea(
                  left: false,
                  right: false,
                  maintainBottomViewPadding: true,
                  minimum: padding,
                  child: mainBoardArea,
                ),
              ),
              Expanded(
                flex: 3,
                child: SafeArea(
                  left: false,
                  maintainBottomViewPadding: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: padding,
                        child: settingsButtonArea,
                      ),
                      Spacer(),
                      Padding(
                        padding: padding,
                        child: restartButtonArea,
                      )
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }
}
