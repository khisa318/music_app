import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/search_screen_shimmer.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/search_suggestions_list.dart';
import '../widgets/search_results_view.dart';
import '../widgets/voice_search_overlay.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/providers/settings_provider.dart';

import '../../data/search_screen_services.dart';
import '../../data/voice_search_service.dart';

class _YouTubeSongWrapper {
  final dynamic _video;

  _YouTubeSongWrapper(this._video);

  String get videoId => _video.id.value;

  String get name => _video.title;

  dynamic get artist =>
      _YouTubeArtistWrapper(_video.author, _video.channelId.value);

  dynamic get thumbnails => [
    _YouTubeThumbnailWrapper(_video.thumbnails.highResUrl, 1280, 720),
  ];

  int get duration => _video.duration?.inSeconds ?? 0;

  bool get isYouTube => true;
}

class _YouTubeArtistWrapper {
  final String _author;
  final String _channelId;

  _YouTubeArtistWrapper(this._author, this._channelId);

  String get name => _author;

  String get artistId => _channelId;
}

class _YouTubeThumbnailWrapper {
  final String _url;
  final int _width;
  final int _height;

  _YouTubeThumbnailWrapper(this._url, this._width, this._height);

  String get url => _url;

  int get width => _width;

  int get height => _height;
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _SliverTabBarDelegate({required this.child, this.height = 48.0});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController _searchController = TextEditingController();

  final FocusNode _focusNode = FocusNode();

  final SearchScreenServices _services = SearchScreenServices();

  final VoiceSearchService _voiceSearchService = VoiceSearchService();

  SearchMode _searchMode = SearchMode.youtubeMusic;

  bool _showVoiceOverlay = false;

  final ValueNotifier<List<String>> _searchHistoryNotifier =
      ValueNotifier<List<String>>([]);

  final ValueNotifier<List<dynamic>> _quickSongsNotifier =
      ValueNotifier<List<dynamic>>([]);

  final ValueNotifier<Map<String, List<dynamic>>> _categorizedResultsNotifier =
      ValueNotifier<Map<String, List<dynamic>>>({
        'Songs': [],
        'Albums': [],
        'Artists': [],
        'Playlists': [],
        'Videos': [],
      });

  final ValueNotifier<List<String>> _searchSuggestionsNotifier =
      ValueNotifier<List<String>>([]);

  final ValueNotifier<bool> _showSuggestionsNotifier = ValueNotifier<bool>(
    false,
  );

  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);

  final ValueNotifier<bool> _hasErrorNotifier = ValueNotifier<bool>(false);

  Timer? _debounceTimer;

  String _errorMessage = '';

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: _getTabCount(), vsync: this);

    _initializeSearchHistory();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  int _getTabCount() {
    return _searchMode == SearchMode.youtube ? 1 : 4;
  }

  Future<void> _initializeSearchHistory() async {
    try {
      final history = await _services.loadSearchHistory();

      if (!mounted) return;

      _searchHistoryNotifier.value = history;
    } catch (e) {
      debugPrint('Failed to load search history: $e');
    }
  }

  Future<void> _onSearchTextChanged(String value) async {
    _debounceTimer?.cancel();

    _showSuggestionsNotifier.value = true;

    final query = value.trim();

    if (query.isEmpty) {
      _searchSuggestionsNotifier.value = [];
      _quickSongsNotifier.value = [];
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      try {
        final suggestions = await _services.fetchSearchSuggestions(
          query,
          _searchMode,
        );

        if (!mounted) return;

        _searchSuggestionsNotifier.value = suggestions;

        if (_searchMode == SearchMode.youtubeMusic) {
          final songs = await _services.fetchQuickSongs(query);

          if (!mounted) return;

          _quickSongsNotifier.value = songs;
        } else {
          _quickSongsNotifier.value = [];
        }
      } catch (e) {
        debugPrint('Search suggestions failed: $e');
      }
    });
  }

  Future<void> _onSearch(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return;
    }

    _isLoadingNotifier.value = true;
    _hasErrorNotifier.value = false;
    _errorMessage = '';

    _showSuggestionsNotifier.value = false;

    try {
      final results = await _services.performSearch(trimmedQuery, _searchMode);

      if (!mounted) return;

      _categorizedResultsNotifier.value = results;

      _isLoadingNotifier.value = false;

      final updatedHistory = await _services.addToSearchHistory(
        _searchHistoryNotifier.value,
        trimmedQuery,
      );

      if (!mounted) return;

      _searchHistoryNotifier.value = updatedHistory;
    } catch (e, stackTrace) {
      debugPrint('Search failed: $e');

      debugPrint('$stackTrace');

      if (!mounted) return;

      _isLoadingNotifier.value = false;
      _hasErrorNotifier.value = true;

      _errorMessage = 'Failed to fetch results. Please try again.';
    }
  }

  Future<void> _onRefresh() async {
    final query = _searchController.text.trim();

    if (query.isNotEmpty) {
      await _onSearch(query);
    }
  }

  Future<void> _removeSearchHistoryItem(String query) async {
    final updatedHistory = await _services.removeFromSearchHistory(
      _searchHistoryNotifier.value,
      query,
    );

    if (!mounted) return;

    _searchHistoryNotifier.value = updatedHistory;
  }

  Future<void> _playSong(dynamic song) async {
    _focusNode.unfocus();

    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    final queueProvider = Provider.of<QueueProvider>(context, listen: false);

    try {
      /*
       * IMPORTANT:
       *
       * SearchScreenServices starts playback first.
       *
       * Radio/related songs are generated in the
       * background and cannot block playback.
       */
      await _services.playSong(song, playerProvider, queueProvider);
    } catch (e, stackTrace) {
      debugPrint('Failed to play song: $e');

      debugPrint('$stackTrace');
    }
  }

  Future<void> _startVoiceSearch() async {
    _focusNode.unfocus();

    if (mounted) {
      setState(() {
        _showVoiceOverlay = true;
      });
    }

    try {
      await _voiceSearchService.startListening(
        onResult: (recognizedText) {
          if (!mounted) return;

          final text = recognizedText.trim();

          setState(() {
            _showVoiceOverlay = false;
          });

          if (text.isEmpty) {
            return;
          }

          _searchController.text = text;

          _showSuggestionsNotifier.value = false;

          _onSearch(text);
        },
        onPartialResult: (_) {},
      );
    } catch (e) {
      debugPrint('Voice search failed: $e');

      if (!mounted) return;

      setState(() {
        _showVoiceOverlay = false;
      });
    }
  }

  void _closeVoiceOverlay() {
    if (!mounted) return;

    setState(() {
      _showVoiceOverlay = false;
    });
  }

  void _clearSearch() {
    _searchController.clear();

    _categorizedResultsNotifier.value = {
      'Songs': [],
      'Albums': [],
      'Artists': [],
      'Playlists': [],
      'Videos': [],
    };

    _searchSuggestionsNotifier.value = [];
    _quickSongsNotifier.value = [];

    _showSuggestionsNotifier.value = false;
    _hasErrorNotifier.value = false;
    _isLoadingNotifier.value = false;
  }

  void _onModeChanged() {
    _tabController.dispose();

    _tabController = TabController(length: _getTabCount(), vsync: this);

    _categorizedResultsNotifier.value = {
      'Songs': [],
      'Albums': [],
      'Artists': [],
      'Playlists': [],
      'Videos': [],
    };

    _searchSuggestionsNotifier.value = [];
    _quickSongsNotifier.value = [];
    _showSuggestionsNotifier.value = false;
    _hasErrorNotifier.value = false;
    _isLoadingNotifier.value = false;

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );

    final accentColor = settingsProvider.accentColor;

    return Theme(
      data: ThemeData(
        scaffoldBackgroundColor: MainScreenColors.getBackgroundColor(
          isDarkMode,
        ),
        cardColor: MainScreenColors.getSurfaceColor(isDarkMode),
        colorScheme: ColorScheme(
          brightness: isDarkMode ? Brightness.dark : Brightness.light,
          primary: accentColor,
          secondary: MainScreenColors.getSecondaryColor(isDarkMode),
          surface: MainScreenColors.getSurfaceColor(isDarkMode),
          error: Colors.red,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: MainScreenColors.getTextColor(isDarkMode),
          onError: Colors.white,
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Consumer<PlayerProvider>(
                builder: (context, playerProvider, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _showSuggestionsNotifier,
                    builder: (context, showSuggestions, _) {
                      return ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, textValue, _) {
                          final shouldShowTabs =
                              textValue.text.trim().isNotEmpty &&
                              !showSuggestions;

                          return RefreshIndicator(
                            color: accentColor,
                            onRefresh: _onRefresh,
                            child: NestedScrollView(
                              headerSliverBuilder: (context, innerBoxIsScrolled) {
                                final slivers = <Widget>[];

                                slivers.add(
                                  SliverToBoxAdapter(
                                    child: SearchBarWidget(
                                      searchController: _searchController,
                                      focusNode: _focusNode,
                                      isDarkMode: isDarkMode,
                                      accentColor: accentColor,
                                      searchMode: _searchMode,
                                      onSearchTextChanged: _onSearchTextChanged,
                                      onSubmitted: (value) {
                                        _focusNode.unfocus();

                                        _showSuggestionsNotifier.value = false;

                                        _onSearch(value);
                                      },
                                      onSearchPressed: () {
                                        _focusNode.unfocus();

                                        _showSuggestionsNotifier.value = false;

                                        _onSearch(_searchController.text);
                                      },
                                      onClearPressed: _clearSearch,
                                      onVoiceSearchPressed: _startVoiceSearch,
                                      onModeChangedToYouTubeMusic: () {
                                        if (_searchMode ==
                                            SearchMode.youtubeMusic) {
                                          return;
                                        }

                                        setState(() {
                                          _searchMode = SearchMode.youtubeMusic;
                                        });

                                        _onModeChanged();
                                      },
                                      onModeChangedToYouTube: () {
                                        if (_searchMode == SearchMode.youtube) {
                                          return;
                                        }

                                        setState(() {
                                          _searchMode = SearchMode.youtube;
                                        });

                                        _onModeChanged();
                                      },
                                    ),
                                  ),
                                );

                                if (shouldShowTabs) {
                                  slivers.add(
                                    SliverPersistentHeader(
                                      pinned: true,
                                      delegate: _SliverTabBarDelegate(
                                        child: Container(
                                          color: Theme.of(
                                            context,
                                          ).scaffoldBackgroundColor,
                                          child: Center(
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth:
                                                    AppDimens.isDesktop(context)
                                                    ? AppDimens.maxContentWidth
                                                    : double.infinity,
                                              ),
                                              child: TabBar(
                                                controller: _tabController,
                                                tabs:
                                                    _searchMode ==
                                                        SearchMode.youtube
                                                    ? const [
                                                        Tab(text: 'Videos'),
                                                      ]
                                                    : const [
                                                        Tab(text: 'Songs'),
                                                        Tab(text: 'Albums'),
                                                        Tab(text: 'Artists'),
                                                        Tab(text: 'Playlists'),
                                                      ],
                                                labelStyle:
                                                    AppTextStyles.titleSm(
                                                      isDarkMode: isDarkMode,
                                                    ),
                                                unselectedLabelStyle:
                                                    AppTextStyles.caption(
                                                      isDarkMode: isDarkMode,
                                                    ),
                                                indicatorColor: accentColor,
                                                labelColor: accentColor,
                                                unselectedLabelColor:
                                                    MainScreenColors.getTextColor(
                                                      isDarkMode,
                                                    ).withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                        ),
                                        height: 48.0,
                                      ),
                                    ),
                                  );
                                }

                                return slivers;
                              },
                              body: _buildContent(isDarkMode, accentColor),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),

              if (_showVoiceOverlay)
                VoiceSearchOverlay(
                  voiceSearchService: _voiceSearchService,
                  accentColor: accentColor,
                  isDarkMode: isDarkMode,
                  onClose: _closeVoiceOverlay,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDarkMode, Color accentColor) {
    return ValueListenableBuilder<bool>(
      valueListenable: _showSuggestionsNotifier,
      builder: (context, showSuggestions, child) {
        if (_searchController.text.trim().isEmpty || showSuggestions) {
          return SearchSuggestionsList(
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            searchText: _searchController.text,
            searchHistoryNotifier: _searchHistoryNotifier,
            searchSuggestionsNotifier: _searchSuggestionsNotifier,
            quickSongsNotifier: _quickSongsNotifier,
            onInitializeSearchHistory: _initializeSearchHistory,
            onSuggestionTapped: (suggestion) {
              _focusNode.unfocus();

              _searchController.text = suggestion;

              _showSuggestionsNotifier.value = false;

              _onSearch(suggestion);
            },
            onHistoryItemTapped: (item) {
              _focusNode.unfocus();

              _searchController.text = item;

              _showSuggestionsNotifier.value = false;

              _onSearch(item);
            },
            onHistoryItemRemoved: _removeSearchHistoryItem,
            onQuickSongTapped: (song) {
              _focusNode.unfocus();

              _playSong(song);
            },
          );
        }

        return ValueListenableBuilder<bool>(
          valueListenable: _isLoadingNotifier,
          builder: (context, isLoading, child) {
            if (isLoading) {
              return _searchController.text.isEmpty
                  ? SearchShimmer.buildHomeShimmer(isDarkMode)
                  : SearchShimmer.buildSearchListShimmer(isDarkMode);
            }

            return ValueListenableBuilder<bool>(
              valueListenable: _hasErrorNotifier,
              builder: (context, hasError, child) {
                if (hasError) {
                  return _buildErrorView(isDarkMode, accentColor);
                }

                return ValueListenableBuilder<Map<String, List<dynamic>>>(
                  valueListenable: _categorizedResultsNotifier,
                  builder: (context, categorizedResults, child) {
                    final hasResults = categorizedResults.values.any(
                      (list) => list.isNotEmpty,
                    );

                    if (hasResults) {
                      return SearchResultsView(
                        tabController: _tabController,
                        searchMode: _searchMode,
                        categorizedResults: categorizedResults,
                        isDarkMode: isDarkMode,
                        accentColor: accentColor,
                        onSongTapped: _playSong,
                        createSongWrapper: (video) =>
                            _YouTubeSongWrapper(video),
                      );
                    }

                    return Center(
                      child: Text(
                        'search_hint'.tr(),
                        style: AppTextStyles.bodyMd(isDarkMode: isDarkMode)
                            .copyWith(
                              color: MainScreenColors.getTextColor(
                                isDarkMode,
                              ).withValues(alpha: 0.5),
                            ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildErrorView(bool isDarkMode, Color accentColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: AppTextStyles.subtitle(isDarkMode: isDarkMode),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: MainScreenColors.getTextColor(isDarkMode),
              ),
              onPressed: () {
                _onSearch(_searchController.text);
              },
              child: Text('Retry', style: AppTextStyles.button()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _voiceSearchService.dispose();

    _debounceTimer?.cancel();

    _searchController.dispose();
    _focusNode.dispose();
    _tabController.dispose();

    _searchHistoryNotifier.dispose();
    _quickSongsNotifier.dispose();
    _categorizedResultsNotifier.dispose();
    _searchSuggestionsNotifier.dispose();
    _showSuggestionsNotifier.dispose();
    _isLoadingNotifier.dispose();
    _hasErrorNotifier.dispose();

    super.dispose();
  }
}
