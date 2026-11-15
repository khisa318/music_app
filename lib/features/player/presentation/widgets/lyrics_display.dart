import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../screens/player_ui.dart';

import '../../../../core/providers/lyrics_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/glass_modal.dart';

/// A single word (or syllable) inside a lyric line. Word timings are only
/// present for enhanced LRC (`<mm:ss.xx>`); otherwise progress is derived from
/// the line's own timeline.
class LyricWord {
  final String text;
  final Duration? start;
  final Duration? end;

  const LyricWord(this.text, {this.start, this.end});
}

class LyricLine {
  final String text;
  final Duration? timestamp;
  final Duration? end;
  final List<LyricWord> words;

  LyricLine({
    required this.text,
    this.timestamp,
    this.end,
    this.words = const [],
  });
}

/// The per-frame playback snapshot that drives the karaoke fill. It is kept in
/// a [ValueNotifier] so a 60 fps tick only rebuilds the line being sung, never
/// the whole list.
class _LyricFrame {
  final int index;
  final double progress;
  final double positionMs;

  const _LyricFrame(this.index, this.progress, this.positionMs);
}

/// Lenis' `easeOutExpo`: the long, soft glide Liquid Lyrics uses between lines.
class _EaseOutExpoCurve extends Curve {
  const _EaseOutExpoCurve();

  @override
  double transformInternal(double t) {
    if (t >= 1.0) return 1.0;
    return 1.0 - math.pow(2.0, -10.0 * t).toDouble();
  }
}

class LyricsDisplay extends StatefulWidget {
  final Stream<Duration> positionStream;
  final VoidCallback onClose;
  final Function(Duration) onSeek;

  const LyricsDisplay({
    super.key,
    required this.positionStream,
    required this.onClose,
    required this.onSeek,
  });

  @override
  State<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends State<LyricsDisplay>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<_LyricFrame> _frame = ValueNotifier(
    const _LyricFrame(-1, 0, 0),
  );
  List<LyricLine> _parsedLyrics = [];
  List<GlobalKey> _lineKeys = [];
  int _currentLineIndex = -1;
  bool _userScrolling = false;
  Timer? _scrollTimer;
  bool _showPlainLyrics = false;
  StreamSubscription<Duration>? _positionSubscription;

  late final AnimationController _entranceController;
  Ticker? _ticker;
  Duration _lastTickElapsed = Duration.zero;

  /// Where the audio actually is, and where the lyrics are painted. Between
  /// player updates the clock is extrapolated so the karaoke sweep moves with
  /// the audio instead of stepping once per position sample.
  Duration _targetPosition = Duration.zero;
  double _displayPositionMs = 0;
  final Stopwatch _playbackClock = Stopwatch()..start();
  int _anchorPositionMs = 0;
  int _anchorAtMs = 0;
  bool _hasPosition = false;

  /// False until the first line has been aligned to the song; the first jump
  /// is instant, later line changes glide.
  bool _hasAnchoredToPlayback = false;

  Object? _lastResponse;
  Object? _lastSongKey;

  late LyricsProvider _lyricsProvider;
  late PlayerProvider _playerProvider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onUserScroll);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();

    _positionSubscription = widget.positionStream.listen(_onPosition);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lyricsProvider = Provider.of<LyricsProvider>(context);
    _playerProvider = Provider.of<PlayerProvider>(context);

    _lyricsProvider.removeListener(_onLyricsProviderChanged);
    _lyricsProvider.addListener(_onLyricsProviderChanged);
    _playerProvider.removeListener(_onPlayerProviderChanged);
    _playerProvider.addListener(_onPlayerProviderChanged);

    _ticker ??= createTicker(_onTick)..start();

    _parseLyrics();
  }

  void _onLyricsProviderChanged() {
    _parseLyrics();
  }

  void _onPlayerProviderChanged() {
    _parseLyrics();
  }

  void _onPosition(Duration position) {
    final diff = (position.inMilliseconds - _displayPositionMs).abs();
    _targetPosition = position;
    _anchorPositionMs = position.inMilliseconds;
    _anchorAtMs = _playbackClock.elapsedMilliseconds;
    _hasPosition = true;
    // A seek should not make the fill crawl across the whole song: snap.
    if (diff > 900) {
      _displayPositionMs = position.inMilliseconds.toDouble();
    }
  }

  void _parseLyrics() {
    final lyricsResponse = _lyricsProvider.lyricsResponse;
    final localSong = _playerProvider.currentLocalSong;
    final songKey =
        _playerProvider.currentSong?.videoId ??
        localSong?['id'] ??
        localSong?['path'];

    if (identical(lyricsResponse, _lastResponse) && songKey == _lastSongKey) {
      return;
    }
    _lastResponse = lyricsResponse;
    _lastSongKey = songKey;

    if (lyricsResponse?.lyrics != null) {
      if (lyricsResponse!.isSynced) {
        _parsedLyrics = _parseSyncedLyrics(lyricsResponse.lyrics);
      } else {
        _parsedLyrics = lyricsResponse.lyrics
            .split('\n')
            .map((line) => LyricLine(text: line))
            .toList();
      }
    } else {
      _parsedLyrics = [];
    }

    _lineKeys = List.generate(_parsedLyrics.length, (_) => GlobalKey());
    _displayPositionMs = _targetPosition.inMilliseconds.toDouble();
    _currentLineIndex = _resolveIndex(_displayPositionMs);
    _frame.value = _LyricFrame(
      _currentLineIndex,
      _progressFor(_currentLineIndex, _displayPositionMs),
      _displayPositionMs,
    );
    _hasAnchoredToPlayback = false;
    _entranceController
      ..reset()
      ..forward();

    if (mounted) {
      setState(() {});
      // Put the first upcoming line in view straight away instead of leaving
      // the list parked at the top spacer, far down the panel.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrentLine(animate: false);
      });
    }
  }

  int _resolveIndex(double positionMs) {
    var index = -1;
    for (var i = 0; i < _parsedLyrics.length; i++) {
      final timestamp = _parsedLyrics[i].timestamp;
      if (timestamp == null) continue;
      if (timestamp.inMilliseconds <= positionMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  double _progressFor(int index, double positionMs) {
    if (index < 0 || index >= _parsedLyrics.length) return 0.0;
    final start = _parsedLyrics[index].timestamp!.inMilliseconds;
    final end = _parsedLyrics[index].end?.inMilliseconds ?? (start + 4500);
    return end > start
        ? ((positionMs - start) / (end - start)).clamp(0.0, 1.0)
        : 1.0;
  }

  static Duration? _durationFromMatch(RegExpMatch match) {
    final minutes = int.tryParse(match.group(1) ?? '');
    final seconds = int.tryParse(match.group(2) ?? '');
    if (minutes == null || seconds == null) return null;
    final fraction = match.group(3) ?? '';
    var millis = 0;
    if (fraction.isNotEmpty) {
      final value = int.tryParse(fraction) ?? 0;
      millis = fraction.length == 1
          ? value * 100
          : fraction.length == 2
          ? value * 10
          : value;
    }
    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  List<LyricLine> _parseSyncedLyrics(String lyrics) {
    final parsedLines = <LyricLine>[];
    final timeTag = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final wordTag = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');

    // LRC files may carry a global timing shift, e.g. `[offset:500]`.
    final offsetMatch = RegExp(
      r'\[offset:\s*([+-]?\d+)\s*\]',
      caseSensitive: false,
    ).firstMatch(lyrics);
    final offset = Duration(
      milliseconds: int.tryParse(offsetMatch?.group(1) ?? '') ?? 0,
    );

    for (final rawLine in lyrics.split('\n')) {
      final match = timeTag.firstMatch(rawLine);
      if (match == null) continue;
      final parsed = _durationFromMatch(match);
      if (parsed == null) continue;
      final timestamp = parsed + offset;

      final content = rawLine.replaceFirst(
        RegExp(r'^(\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\])+'),
        '',
      );
      final wordMatches = wordTag.allMatches(content).toList();
      final text = content.replaceAll(wordTag, '').trim();
      if (text.isEmpty && wordMatches.isEmpty) continue;

      final words = <LyricWord>[];
      if (wordMatches.isNotEmpty) {
        for (var i = 0; i < wordMatches.length; i++) {
          final wordMatch = wordMatches[i];
          final wordStart = _durationFromMatch(wordMatch);
          final start = wordStart == null ? null : wordStart + offset;
          final textStart = wordMatch.end;
          final textEnd = i + 1 < wordMatches.length
              ? wordMatches[i + 1].start
              : content.length;
          final wordText = content.substring(textStart, textEnd).trim();
          if (wordText.isEmpty) continue;
          words.add(LyricWord(wordText, start: start));
        }
        for (var i = 0; i < words.length; i++) {
          final start = words[i].start;
          if (start == null) continue;
          final end = i + 1 < words.length
              ? words[i + 1].start
              : timestamp + const Duration(milliseconds: 4500);
          words[i] = LyricWord(words[i].text, start: start, end: end);
        }
      } else if (text.isNotEmpty) {
        words.addAll(
          text
              .split(RegExp(r'\s+'))
              .where((word) => word.isNotEmpty)
              .map((word) => LyricWord(word)),
        );
      }

      parsedLines.add(
        LyricLine(text: text, timestamp: timestamp, words: words),
      );
    }

    final withEnds = <LyricLine>[];
    for (var i = 0; i < parsedLines.length; i++) {
      final start = parsedLines[i].timestamp!;
      var end = i + 1 < parsedLines.length
          ? parsedLines[i + 1].timestamp!
          : start + const Duration(milliseconds: 4500);
      // Guard against duplicate timestamps collapsing a line to zero length.
      if (end <= start) {
        end = start + const Duration(milliseconds: 1200);
      }
      withEnds.add(
        LyricLine(
          text: parsedLines[i].text,
          timestamp: start,
          end: end,
          words: parsedLines[i].words,
        ),
      );
    }

    return withEnds;
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastTickElapsed).inMicroseconds / 1000.0;
    _lastTickElapsed = elapsed;
    if (dtMs <= 0 || !mounted) return;

    // Extrapolate from the last position sample so the words move with the
    // audio between player updates, then ease out any jitter.
    var targetMs = _anchorPositionMs.toDouble();
    if (_hasPosition && _playerProvider.playerService.isPlaying) {
      targetMs += (_playbackClock.elapsedMilliseconds - _anchorAtMs).toDouble();
    }
    final smoothing = 1 - math.exp(-dtMs.clamp(0.0, 120.0) / 90.0);
    _displayPositionMs += (targetMs - _displayPositionMs) * smoothing;

    if (_showPlainLyrics) return;
    if (!(_lyricsProvider.lyricsResponse?.isSynced ?? false) ||
        _parsedLyrics.isEmpty) {
      return;
    }

    final positionMs = _displayPositionMs;
    final index = _resolveIndex(positionMs);
    final progress = _progressFor(index, positionMs);

    if (index != _currentLineIndex) {
      final firstAnchor = !_hasAnchoredToPlayback;
      _currentLineIndex = index;
      _frame.value = _LyricFrame(index, progress, positionMs);
      setState(() {});
      if (!_userScrolling) {
        _scrollToCurrentLine(animate: !firstAnchor);
      }
      _hasAnchoredToPlayback = true;
    } else if (index >= 0 &&
        (positionMs - _frame.value.positionMs).abs() >= 3.0) {
      _frame.value = _LyricFrame(index, progress, positionMs);
    }
  }

  void _onUserScroll() {
    if (!_scrollController.hasClients) return;

    final direction = _scrollController.position.userScrollDirection;
    if (direction != ScrollDirection.idle) {
      // Reading ahead wins over following the song, for a moment after the
      // finger (or its momentum) stops moving the list.
      _scrollTimer?.cancel();
      if (!_userScrolling) {
        setState(() => _userScrolling = true);
      }
      return;
    }

    if (!_userScrolling) return;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 5000), () {
      if (!mounted) return;
      setState(() => _userScrolling = false);
      _displayPositionMs = _targetPosition.inMilliseconds.toDouble();
      _scrollToCurrentLine();
    });
  }

  void _scrollToCurrentLine({bool animate = true}) {
    if (!_scrollController.hasClients || _parsedLyrics.isEmpty) return;

    // Before the first timestamp there is nothing "current" yet, so keep the
    // first upcoming line in view rather than leaving the list at the top
    // spacer near the bottom of the panel.
    final targetIndex = _currentLineIndex >= 0 ? _currentLineIndex : 0;
    if (targetIndex >= _parsedLyrics.length) return;
    final key = _lineKeys[targetIndex];

    void performScroll() {
      if (key.currentContext == null) return;
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: animate ? const Duration(milliseconds: 620) : Duration.zero,
        curve: animate ? const _EaseOutExpoCurve() : Curves.linear,
        alignment: 0.5,
      );
    }

    if (key.currentContext != null) {
      performScroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) performScroll();
      });
    }
  }

  void _togglePlainLyrics() {
    setState(() {
      _showPlainLyrics = !_showPlainLyrics;
    });

    if (!_showPlainLyrics) {
      _displayPositionMs = _targetPosition.inMilliseconds.toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentLine();
      });
    }
  }

  void _seekToLine(int lineIndex) {
    if ((_lyricsProvider.lyricsResponse?.isSynced ?? false) &&
        lineIndex >= 0 &&
        lineIndex < _parsedLyrics.length &&
        _parsedLyrics[lineIndex].timestamp != null) {
      widget.onSeek(_parsedLyrics[lineIndex].timestamp!);
    }
  }

  String _formatLyricsError(String? error, String provider) {
    if (error == null || error.isEmpty) return 'Lyrics not found';
    if (provider.toLowerCase().contains('lrclib')) {
      final statusMatch = RegExp(r'status code of (\d{3})').firstMatch(error);
      if (statusMatch != null) {
        final code = statusMatch.group(1);
        if (code == '404') return 'Lyrics not found (404).';
        return 'Failed to load lyrics (HTTP $code).';
      }

      if (error.contains('DioException')) {
        return 'Network error while fetching lyrics (LRCLib).';
      }
      final single = error.replaceAll('\n', ' ').trim();
      final firstSentence = single.split('.').first;
      return firstSentence.length <= 120
          ? firstSentence
          : '${firstSentence.substring(0, 116)}...';
    }
    final single = error.replaceAll('\n', ' ').trim();
    return single.length <= 140 ? single : '${single.substring(0, 136)}...';
  }

  List<Widget> _buildLyricsLines(Color accentColor, double fontSize) {
    final isSynced = _lyricsProvider.lyricsResponse?.isSynced ?? false;
    final activeIndex = _currentLineIndex;

    return List<Widget>.generate(_parsedLyrics.length, (i) {
      final line = _parsedLyrics[i];
      final isActive = isSynced && i == activeIndex;
      final isPast = activeIndex >= 0 && i < activeIndex;
      return _LiquidLyricLine(
        key: _lineKeys[i],
        line: line,
        isActive: isActive,
        isPast: isPast,
        isStatic: line.timestamp == null,
        fontSize: fontSize,
        accentColor: accentColor,
        frame: isActive ? _frame : null,
        onTap: isSynced && line.timestamp != null ? () => _seekToLine(i) : null,
      );
    });
  }

  /// Liquid Lyrics' content entrance: arrives from below with a short blur,
  /// overshoots a touch, then settles.
  Widget _entrance(Widget child) {
    return AnimatedBuilder(
      animation: _entranceController,
      child: child,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_entranceController.value);
        if (v >= 0.999) return child!;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(18 * (1 - v), 24 * (1 - v)),
            child: Transform.scale(
              scale: 0.972 + 0.028 * v,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 7 * (1 - v),
                  sigmaY: 7 * (1 - v),
                  tileMode: TileMode.decal,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    final accentColor = settingsProvider.accentColor;
    final playerProvider = Provider.of<PlayerProvider>(context);

    final mq = MediaQuery.of(context);
    final double textScale = mq.textScaler.scale(1.0);
    final double navIconScale = textScale > 1.0
        ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
        : 1.0;
    final double lyricsFontSize =
        (mq.size.width * 0.075).clamp(27.0, 36.0).toDouble() *
        textScale.clamp(1.0, 1.15);

    final hasPlayer =
        playerProvider.currentSong != null ||
        playerProvider.lastPlayedSong != null ||
        playerProvider.currentLocalSong != null;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppDimens.radiusXxxl),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: _LyricsBackdrop(
              thumbnail: playerProvider.currentThumbnail,
              accentColor: accentColor,
            ),
          ),
          Column(
            children: [
              const SizedBox(height: AppDimens.spacingSm),
              Container(
                width: AppDimens.dragHandleWidth,
                height: AppDimens.dragHandleHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
              ),
              _LyricsHeader(
                title: playerProvider.currentTitle,
                artist: playerProvider.currentArtist,
                isPlainLyrics: _showPlainLyrics,
                onTogglePlainLyrics: _togglePlainLyrics,
                onRefresh: () async {
                  setState(() {});
                  await _lyricsProvider.fetchLyricsForCurrentSong(
                    forceRefresh: true,
                  );
                },
                onClose: widget.onClose,
              ),

              Center(
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
                  child: Consumer<SettingsProvider>(
                    builder: (context, settings, child) {
                      final isLocalSong =
                          playerProvider.currentLocalSong != null;
                      final currentProvider = settings.lyricsProvider;

                      final List<String> availableProviders = isLocalSong
                          ? ['LRCLib']
                          : ['LRCLib', 'YT Music'];

                      double highlightWidth = 0;
                      double highlightLeft = 0;
                      final double totalWidth = AppDimens.buttonWidthMedium;
                      double itemWidth = totalWidth / availableProviders.length;

                      int selectedIndex = availableProviders.indexOf(
                        currentProvider,
                      );
                      if (selectedIndex == -1) {
                        selectedIndex = 0;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          settings.lyricsProvider = 'LRCLib';
                          _lyricsProvider.fetchLyricsForCurrentSong();
                        });
                      }

                      // A single source is not a choice: the switch would be a
                      // lone pill pretending to be interactive.
                      if (availableProviders.length < 2) {
                        return const SizedBox.shrink();
                      }

                      highlightWidth = itemWidth - AppDimens.spacingS;
                      highlightLeft =
                          (selectedIndex * itemWidth) + AppDimens.spacingXs;

                      final double providerTextScale = textScale > 1.0
                          ? (1.0 / textScale).clamp(0.70, 1.0).toDouble()
                          : 1.0;

                      return Container(
                        width: totalWidth,
                        height: AppDimens.buttonSizeCompact,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusXxl,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: AppDimens.borderWidthThin,
                          ),
                        ),
                        child: Stack(
                          children: [
                            AnimatedPositioned(
                              duration: AppDimens.animDefault,
                              curve: Curves.easeOutCubic,
                              left: highlightLeft,
                              top: AppDimens.spacingXs,
                              width: highlightWidth,
                              child: Container(
                                height: AppDimens.iconXl,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusMdLg,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Row(
                                children: availableProviders.map((provider) {
                                  final isSelected =
                                      currentProvider == provider;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () async {
                                        final alreadyTried = _lyricsProvider
                                            .hasTriedProvider(provider);

                                        settings.lyricsProvider = provider;
                                        setState(() {});

                                        if (alreadyTried) {
                                          await _lyricsProvider
                                              .loadCachedLyricsForProvider(
                                                provider,
                                              );
                                        } else {
                                          await _lyricsProvider
                                              .fetchLyricsForCurrentSong();
                                        }
                                      },
                                      child: Center(
                                        child: Text(
                                          provider,
                                          textScaler: TextScaler.linear(
                                            providerTextScale,
                                          ),
                                          style: GoogleFonts.manrope(
                                            fontSize: 11.5,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            letterSpacing: 0.2,
                                            color: isSelected
                                                ? Colors.black.withValues(
                                                    alpha: 0.82,
                                                  )
                                                : Colors.white.withValues(
                                                    alpha: 0.62,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              Expanded(
                child: Stack(
                  children: [
                    if (_lyricsProvider.isLoading)
                      const SizedBox.expand(child: _LyricsSkeleton())
                    else if (_lyricsProvider.lyricsResponse?.lyrics == null ||
                        _lyricsProvider.lyricsResponse!.lyrics.isEmpty)
                      SizedBox.expand(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.06),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.10),
                                  ),
                                ),
                                child: Icon(
                                  Icons.music_off_rounded,
                                  color: Colors.white.withValues(alpha: 0.55),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: AppDimens.spacingLg),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppDimens.paddingXxl,
                                ),
                                child: Text(
                                  _formatLyricsError(
                                    _lyricsProvider.error,
                                    settingsProvider.lyricsProvider,
                                  ),
                                  style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(height: AppDimens.spacingSm),
                              if (_lyricsProvider.error != null &&
                                  _lyricsProvider.error!.length > 120)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: accentColor,
                                  ),
                                  onPressed: () => showGlassDialog<void>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Error details'),
                                      content: SingleChildScrollView(
                                        child: SelectableText(
                                          _lyricsProvider.error!,
                                          style: AppTextStyles.finePrintBase()
                                              .copyWith(
                                                fontSize:
                                                    AppTextStyles.fontSizeXs,
                                              ),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          child: Text(
                                            'Close',
                                            style: TextStyle(
                                              color: accentColor,
                                              fontWeight:
                                                  AppTextStyles.weightSemiBold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    'Show details',
                                    style: GoogleFonts.manrope(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              Text(
                                'from ${settingsProvider.lyricsProvider}',
                                style: GoogleFonts.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.1,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        child: _showPlainLyrics
                            ? SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  AppDimens.paddingXxl,
                                  AppDimens.paddingLg,
                                  AppDimens.paddingXxl,
                                  AppDimens.paddingXxl,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 680,
                                    ),
                                    child: Text(
                                      _lyricsProvider.lyricsResponse!.lyrics,
                                      style: GoogleFonts.manrope(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.8,
                                        letterSpacing: 0.05,
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              )
                            : ShaderMask(
                                // The words melt into the panel at both
                                // edges instead of being chopped off.
                                shaderCallback: (rect) => const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.white,
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                  stops: [0.0, 0.11, 0.82, 1.0],
                                ).createShader(rect),
                                blendMode: BlendMode.dstIn,
                                child: Center(
                                  child: _entrance(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 720,
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          // Size the lead-in/trailing gaps to
                                          // the lyrics viewport, not the whole
                                          // screen, so the first line starts
                                          // near the middle instead of ~75%
                                          // down the panel.
                                          final double spacer =
                                              constraints.maxHeight * 0.44;
                                          return SingleChildScrollView(
                                            controller: _scrollController,
                                            physics: const BouncingScrollPhysics(
                                              parent:
                                                  AlwaysScrollableScrollPhysics(),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                SizedBox(height: spacer),
                                                ..._buildLyricsLines(
                                                  accentColor,
                                                  lyricsFontSize,
                                                ),
                                                SizedBox(height: spacer),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
              ),

              if (hasPlayer)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    border: const Border(
                      top: BorderSide(color: Color(0x14FFFFFF)),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: AppDimens.miniPlayerHeight * navIconScale,
                      child: PlayerUI(
                        showFullScreen: false,
                        isEmbedded: true,
                        onMinimize: () {},
                        onExpand: () => widget.onClose(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onUserScroll);
    _scrollController.dispose();
    _scrollTimer?.cancel();
    _ticker?.dispose();
    _entranceController.dispose();
    _frame.dispose();
    _positionSubscription?.cancel();
    _lyricsProvider.removeListener(_onLyricsProviderChanged);
    _playerProvider.removeListener(_onPlayerProviderChanged);
    super.dispose();
  }
}

/// One line of the Liquid-Lyrics-style list.
///
/// The line being sung is rendered word by word: each word carries a horizontal
/// karaoke wipe, rises on a soft sine arc as it is sung, and cools back down
/// once it passes. Neighbouring lines rest faint and slightly small, and the
/// handover is eased over ~600 ms. A tap seeks when the line has a timestamp.
class _LiquidLyricLine extends StatelessWidget {
  final LyricLine line;
  final bool isActive;
  final bool isPast;
  final bool isStatic;
  final double fontSize;
  final Color accentColor;
  final ValueNotifier<_LyricFrame>? frame;
  final VoidCallback? onTap;

  const _LiquidLyricLine({
    super.key,
    required this.line,
    required this.isActive,
    required this.isPast,
    required this.isStatic,
    required this.fontSize,
    required this.accentColor,
    this.frame,
    this.onTap,
  });

  static const Cubic _ease = Cubic(0.16, 1, 0.3, 1);
  static const double _activeScale = 1.07;
  static const double _restScale = 0.955;

  TextStyle _style(Color color) => GoogleFonts.manrope(
    fontSize: fontSize,
    height: 1.24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: color,
  );

  @override
  Widget build(BuildContext context) {
    final opacity = isActive ? 1.0 : (isStatic ? 0.72 : 0.28);
    final restingColor = isActive
        ? Colors.white
        : isStatic
        ? Colors.white.withValues(alpha: 0.85)
        : isPast
        ? Colors.white
        : Colors.white.withValues(alpha: 0.28);

    Widget content;
    if (isActive && frame != null && line.words.isNotEmpty) {
      content = ValueListenableBuilder<_LyricFrame>(
        valueListenable: frame!,
        builder: (context, value, _) => _buildActiveWords(value),
      );
    } else {
      content = Text(
        line.text,
        textAlign: TextAlign.center,
        style: _style(restingColor),
      );
    }

    return Semantics(
      button: onTap != null,
      label: line.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 520),
          curve: _ease,
          opacity: opacity,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: isActive ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 620),
            curve: _ease,
            builder: (context, t, child) {
              return Transform.translate(
                offset: Offset(0, -2.0 * t),
                child: Transform.scale(
                  scale: _restScale + (_activeScale - _restScale) * t,
                  alignment: Alignment.center,
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveWords(_LyricFrame value) {
    final words = line.words;
    final total = words.fold<int>(
      0,
      (sum, word) => sum + math.max(1, word.text.length),
    );
    var cumulative = 0;
    final children = <Widget>[];

    for (final word in words) {
      final weight = math.max(1, word.text.length);
      final startFraction = total == 0 ? 0.0 : cumulative / total;
      cumulative += weight;
      final endFraction = total == 0 ? 1.0 : cumulative / total;

      double wordProgress;
      final wordStart = word.start;
      if (wordStart != null) {
        final startMs = wordStart.inMilliseconds.toDouble();
        final endMs =
            word.end?.inMilliseconds.toDouble() ??
            (line.end?.inMilliseconds.toDouble() ?? startMs + 400);
        wordProgress = endMs > startMs
            ? ((value.positionMs - startMs) / (endMs - startMs)).clamp(0.0, 1.0)
            : (value.positionMs >= startMs ? 1.0 : 0.0);
      } else {
        final span = endFraction - startFraction;
        wordProgress = span > 0
            ? ((value.progress - startFraction) / span).clamp(0.0, 1.0)
            : value.progress;
      }

      children.add(
        _KaraokeWord(
          text: word.text,
          progress: wordProgress,
          style: _style(Colors.white),
          accentColor: accentColor,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: fontSize * 0.26,
      runSpacing: fontSize * 0.12,
      children: children,
    );
  }
}

/// A single word with Liquid Lyrics' per-word motion: a horizontal karaoke
/// wipe, a sine-shaped lift and scale while it is being sung, and a soft halo
/// that blooms at the head of the fill.
class _KaraokeWord extends StatelessWidget {
  final String text;
  final double progress;
  final TextStyle style;
  final Color accentColor;

  const _KaraokeWord({
    required this.text,
    required this.progress,
    required this.style,
    required this.accentColor,
  });

  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final r = math.sin(p * math.pi);
    final lift = -5.0 * r;
    final scale = 1.0 + 0.018 * r;
    final glow = _smoothstep(0.0, 0.15, r) * (1 - _smoothstep(0.6, 1.0, r));
    final dim = Colors.white.withValues(alpha: 0.32);

    Widget fill;
    if (p <= 0.001) {
      fill = Text(text, style: style.copyWith(color: dim));
    } else if (p >= 0.999) {
      fill = Text(text, style: style.copyWith(color: Colors.white));
    } else {
      fill = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Colors.white, dim, dim],
          stops: [0.0, p, math.min(1.0, p + 0.2), 1.0],
        ).createShader(rect),
        child: Text(text, style: style.copyWith(color: Colors.white)),
      );
    }

    Widget content = fill;
    if (glow > 0.02) {
      content = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: Text(
              text,
              style: style.copyWith(
                color: Colors.transparent,
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.5 * glow),
                    blurRadius: 10 * glow,
                  ),
                  Shadow(
                    color: accentColor.withValues(alpha: 0.22 * glow),
                    blurRadius: 22 * glow,
                  ),
                ],
              ),
            ),
          ),
          fill,
        ],
      );
    }

    return Transform.translate(
      offset: Offset(0, lift),
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        child: content,
      ),
    );
  }
}

/// The blurred artwork wash behind the words: the playing track's cover
/// scattered into colour, under a dark scrim and a breath of the accent colour.
class _LyricsBackdrop extends StatelessWidget {
  final String thumbnail;
  final Color accentColor;

  const _LyricsBackdrop({required this.thumbnail, required this.accentColor});

  static bool _isRemote(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  /// A gentler cousin of Kawarp: the artwork is pushed a little past life so
  /// the moving dark scrim reads as colour drift rather than a grey wash.
  static const ColorFilter _saturation = ColorFilter.matrix(<double>[
    1.2756, -0.2503, -0.0253, 0, 0, //
    -0.0744, 1.0997, -0.0253, 0, 0, //
    -0.0744, -0.2503, 1.3247, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final hasArtwork = _isRemote(thumbnail);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF17171F), Color(0xFF08080B)],
            ),
          ),
        ),
        if (hasArtwork)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 46,
                sigmaY: 46,
                tileMode: TileMode.decal,
              ),
              child: Transform.scale(
                scale: 1.45,
                child: ColorFiltered(
                  colorFilter: _saturation,
                  child: CachedNetworkImage(
                    imageUrl: thumbnail,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 400),
                    placeholder: (context, url) => const SizedBox.shrink(),
                    errorWidget: (context, url, error) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Color(0xB8000000), Color(0xF0000000)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, -1.05),
              radius: 1.15,
              colors: [accentColor.withValues(alpha: 0.22), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

/// Song identity and the three tools, in one quiet line above the words.
class _LyricsHeader extends StatelessWidget {
  final String title;
  final String artist;
  final bool isPlainLyrics;
  final VoidCallback onTogglePlainLyrics;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  const _LyricsHeader({
    required this.title,
    required this.artist,
    required this.isPlainLyrics,
    required this.onTogglePlainLyrics,
    required this.onRefresh,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'lyrics'.tr().toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.0,
                        color: Colors.white.withValues(alpha: 0.42),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: Colors.white.withValues(alpha: 0.96),
                  ),
                ),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppDimens.spacingSm),
          _LyricsIconButton(
            icon: isPlainLyrics
                ? Icons.format_list_bulleted_rounded
                : Icons.lyrics_outlined,
            onPressed: onTogglePlainLyrics,
          ),
          const SizedBox(width: AppDimens.spacingXs),
          _LyricsIconButton(icon: Icons.refresh_rounded, onPressed: onRefresh),
          const SizedBox(width: AppDimens.spacingXs),
          _LyricsIconButton(icon: Icons.close_rounded, onPressed: onClose),
        ],
      ),
    );
  }
}

/// A round glass button for the lyrics chrome.
class _LyricsIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _LyricsIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      shape: const CircleBorder(side: BorderSide(color: Color(0x1FFFFFFF))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 17,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// Placeholder lines while the first source is still answering.
class _LyricsSkeleton extends StatefulWidget {
  const _LyricsSkeleton();

  @override
  State<_LyricsSkeleton> createState() => _LyricsSkeletonState();
}

class _LyricsSkeletonState extends State<_LyricsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  static const List<double> _widths = [0.62, 0.78, 0.5, 0.7, 0.44];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity:
                0.35 + 0.45 * Curves.easeInOut.transform(_controller.value),
            child: child,
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < _widths.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                FractionallySizedBox(
                  widthFactor: _widths[i],
                  alignment: Alignment.center,
                  child: Container(
                    height: 13,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
