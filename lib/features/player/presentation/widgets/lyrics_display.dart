import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../screens/player_ui.dart';

import '../../../../core/providers/lyrics_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/glass_modal.dart';

class LyricLine {
  final String text;
  final Duration? timestamp;

  LyricLine({required this.text, this.timestamp});
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

class _LyricsDisplayState extends State<LyricsDisplay> {
  final ScrollController _scrollController = ScrollController();
  List<LyricLine> _parsedLyrics = [];
  List<GlobalKey> _lineKeys = [];
  int _currentLineIndex = 0;
  bool _userScrolling = false;
  Timer? _scrollTimer;
  bool _showPlainLyrics = false;
  StreamSubscription<Duration>? _positionSubscription;

  Duration _lastPosition = Duration.zero;

  late LyricsProvider _lyricsProvider;
  late PlayerProvider _playerProvider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onUserScroll);

    _positionSubscription = widget.positionStream.listen((position) {
      _lastPosition = position;
      if (!_userScrolling && !_showPlainLyrics) {
        _updateCurrentLine(position);
      }
    });
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

    _parseLyrics();
  }

  void _onLyricsProviderChanged() {
    _parseLyrics();
  }

  void _onPlayerProviderChanged() {
    _parseLyrics();
  }

  void _parseLyrics() {
    final lyricsResponse = _lyricsProvider.lyricsResponse;
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

    if (mounted) {
      setState(() {});
    }
  }

  List<LyricLine> _parseSyncedLyrics(String lyrics) {
    final lines = lyrics.split('\n');
    final parsedLines = <LyricLine>[];

    for (var line in lines) {
      final match = RegExp(
        r'\[(\d{2}):(\d{2})\.(\d{2})\](.*)',
      ).firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = int.parse(match.group(3)!) * 10;
        final text = match.group(4)!.trim();

        if (text.isNotEmpty) {
          parsedLines.add(
            LyricLine(
              text: text,
              timestamp: Duration(
                minutes: minutes,
                seconds: seconds,
                milliseconds: milliseconds,
              ),
            ),
          );
        }
      }
    }

    return parsedLines;
  }

  void _onUserScroll() {
    if (!_scrollController.hasClients) return;

    final direction = _scrollController.position.userScrollDirection;
    if (direction != ScrollDirection.idle) {
      // Reading ahead wins over following the song, but only while the finger
      // (or its momentum) is moving the list.
      _scrollTimer?.cancel();
      if (!_userScrolling) {
        setState(() => _userScrolling = true);
      }
      return;
    }

    if (!_userScrolling) return;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(() => _userScrolling = false);
      _updateCurrentLine(_lastPosition);
      _scrollToCurrentLine();
    });
  }

  void _updateCurrentLine(Duration position) {
    final lyricsProvider = Provider.of<LyricsProvider>(context, listen: false);
    if (!(lyricsProvider.lyricsResponse?.isSynced ?? false) ||
        _showPlainLyrics) {
      return;
    }

    int newLineIndex = _parsedLyrics.indexWhere(
      (line) => line.timestamp != null && line.timestamp! > position,
    );

    if (newLineIndex == -1) {
      newLineIndex = _parsedLyrics.length - 1;
    } else if (newLineIndex > 0) {
      newLineIndex--;
    }

    if (newLineIndex != _currentLineIndex) {
      setState(() {
        _currentLineIndex = newLineIndex;
      });

      if (!_userScrolling) {
        _scrollToCurrentLine();
      }
    }
  }

  void _scrollToCurrentLine() {
    if (_scrollController.hasClients &&
        _currentLineIndex < _parsedLyrics.length &&
        _currentLineIndex >= 0) {
      final key = _lineKeys[_currentLineIndex];

      void performScroll() {
        if (key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: AppDimens.animSmooth,
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          );
        }
      }

      if (key.currentContext != null) {
        performScroll();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) performScroll();
        });
      }
    }
  }

  void _togglePlainLyrics() {
    setState(() {
      _showPlainLyrics = !_showPlainLyrics;
    });

    if (!_showPlainLyrics) {
      _scrollToCurrentLine();
    }
  }

  void _seekToLine(int lineIndex) {
    if (_lyricsProvider.lyricsResponse!.isSynced &&
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

  List<Widget> _buildLyricsLines(Color accentColor) {
    final canSeek = _lyricsProvider.lyricsResponse?.isSynced ?? false;
    final activeIndex = _parsedLyrics.isEmpty
        ? -1
        : _currentLineIndex.clamp(0, _parsedLyrics.length - 1);

    return List<Widget>.generate(_parsedLyrics.length, (i) {
      final distance = activeIndex < 0 ? 99 : (i - activeIndex).abs();
      final timestamp = _parsedLyrics[i].timestamp;
      return _LyricLineTile(
        key: _lineKeys[i],
        text: _parsedLyrics[i].text,
        isActive: distance == 0,
        distance: distance,
        isReadingAhead: _userScrolling,
        accentColor: accentColor,
        onTap: canSeek && timestamp != null ? () => _seekToLine(i) : null,
      );
    });
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
                                  stops: [0.0, 0.08, 0.92, 1.0],
                                ).createShader(rect),
                                blendMode: BlendMode.dstIn,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 720,
                                    ),
                                    child: SingleChildScrollView(
                                      controller: _scrollController,
                                      physics: const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            height: mq.size.height * 0.42,
                                          ),
                                          ..._buildLyricsLines(accentColor),
                                          SizedBox(
                                            height: mq.size.height * 0.42,
                                          ),
                                        ],
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
    _positionSubscription?.cancel();
    _lyricsProvider.removeListener(_onLyricsProviderChanged);
    _playerProvider.removeListener(_onPlayerProviderChanged);
    super.dispose();
  }
}

/// One line of the immersive lyrics list.
///
/// Mirrors Orpheon's panel: the line being sung is crisp and full-weight, and
/// the lines around it fall away by distance — dimmer, fractionally smaller and
/// softly blurred — so the eye is drawn to the present line without losing the
/// ones on either side. A tap seeks to the line when its timing is known.
class _LyricLineTile extends StatelessWidget {
  final String text;
  final bool isActive;
  final int distance;

  /// True while the list is being scrolled by hand: the blur clears and every
  /// line becomes readable, so reading ahead is not punished.
  final bool isReadingAhead;
  final Color accentColor;
  final VoidCallback? onTap;

  const _LyricLineTile({
    super.key,
    required this.text,
    required this.isActive,
    required this.distance,
    required this.isReadingAhead,
    required this.accentColor,
    this.onTap,
  });

  /// How the stack falls away either side of the playing line, indexed by
  /// distance from it. The two lines around the playing one stay legible so
  /// you can read ahead and behind; the last entry covers everything further.
  static const List<double> _alphaFalloff = [1.0, 0.8, 0.7, 0.58, 0.46];
  static const List<double> _blurFalloff = [0.0, 1.0, 1.0, 1.7, 2.4];

  /// The playing line sits at 1; the rest sit fractionally back from it.
  static const double _inactiveScale = 0.98;

  double get _alpha => distance < _alphaFalloff.length
      ? _alphaFalloff[distance]
      : _alphaFalloff.last;

  double get _blur => distance < _blurFalloff.length
      ? _blurFalloff[distance]
      : _blurFalloff.last;

  @override
  Widget build(BuildContext context) {
    final alpha = isReadingAhead ? (isActive ? 1.0 : 0.88) : _alpha;
    final blur = isReadingAhead ? 0.0 : _blur;

    // Orpheon's lyric type: one big, tight size for every line, with the
    // playing line separated by weight, light and focus rather than by a
    // smaller font. The stack reads as a single block of words, not a list.
    final style = GoogleFonts.manrope(
      fontSize: 29.0,
      height: 1.22,
      letterSpacing: isActive ? -0.7 : -0.5,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
      color: Colors.white.withValues(alpha: alpha),
      shadows: [
        Shadow(
          color: isActive
              ? accentColor.withValues(alpha: 0.35)
              : Colors.transparent,
          blurRadius: isActive ? 18 : 0,
        ),
      ],
    );

    Widget line = AnimatedDefaultTextStyle(
      duration: AppDimens.animSmooth,
      curve: Curves.easeOutCubic,
      style: style,
      child: Text(text, textAlign: TextAlign.center),
    );

    line = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: blur),
      duration: AppDimens.animSmooth,
      curve: Curves.easeOutCubic,
      child: line,
      builder: (context, sigma, child) {
        if (sigma <= 0.01) return child!;
        return ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: child,
        );
      },
    );

    return Semantics(
      button: onTap != null,
      label: text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: isActive || isReadingAhead ? 1.0 : _inactiveScale,
          duration: AppDimens.animSmooth,
          curve: Curves.easeOutCubic,
          child: AnimatedPadding(
            duration: AppDimens.animSmooth,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: AppDimens.paddingXxl,
              vertical: isActive ? AppDimens.spacingMd : AppDimens.spacingSm,
            ),
            child: line,
          ),
        ),
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
                sigmaX: 52,
                sigmaY: 52,
                tileMode: TileMode.decal,
              ),
              child: Transform.scale(
                scale: 1.4,
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 400),
                  placeholder: (context, url) => const SizedBox.shrink(),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
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
