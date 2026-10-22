import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/services/local_songs_service.dart';
import '../../../../core/widgets/glass_modal.dart';
import '../../../../shared/components/app_snackbar.dart';
import '../screens/metadata_editor_screen.dart';

class LocalSongOptionsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> song;
  final bool isDarkMode;
  final VoidCallback onPlay;

  const LocalSongOptionsBottomSheet({
    super.key,
    required this.song,
    required this.isDarkMode,
    required this.onPlay,
  });

  @override
  State<LocalSongOptionsBottomSheet> createState() =>
      _LocalSongOptionsBottomSheetState();
}

class _LocalSongOptionsBottomSheetState
    extends State<LocalSongOptionsBottomSheet> {
  Uint8List? _artwork;

  String get _title =>
      widget.song['title'] ?? widget.song['name'] ?? 'Unknown Title';
  String get _artist => widget.song['artist'] ?? 'unknown_artist'.tr();
  String get _localPath => widget.song['localPath'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  Future<void> _loadArtwork() async {
    final id = int.tryParse(widget.song['id']?.toString() ?? '');
    if (id == null) return;
    try {
      final bytes = await LocalSongsService().queryArtwork(id);
      if (mounted && bytes != null) setState(() => _artwork = bytes);
    } catch (_) {}
  }

  String get _youtubeSearchLink {
    final query = [_title, _artist]
        .where((part) => part.isNotEmpty && part != 'Unknown Title')
        .join(' ')
        .trim();
    return 'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}';
  }

  String get _youtubeMusicSearchLink {
    final query = [_title, _artist]
        .where((part) => part.isNotEmpty && part != 'Unknown Title')
        .join(' ')
        .trim();
    return 'https://music.youtube.com/search?q=${Uri.encodeQueryComponent(query)}';
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnackBar.showSuccess(context, '$label copied to clipboard');
  }

  Future<void> _shareSong() async {
    const appLink = 'https://musix-website.vercel.app/';
    final text =
        '🎵 Listening to "$_title" by $_artist\n\nDownload MusiX: $appLink 🎶';
    try {
      if (_localPath.isNotEmpty && File(_localPath).existsSync()) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(_localPath)], text: text),
        );
        return;
      }
    } catch (_) {}
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: GlassSheet(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(textColor, isDarkMode),
              _buildOption(
                icon: Icons.play_arrow,
                text: 'play'.tr(),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(context);
                  widget.onPlay();
                },
              ),
              _buildOpenInOptions(textColor, isDarkMode),
              _buildOption(
                icon: Icons.share,
                text: 'share'.tr(),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(context);
                  _shareSong();
                },
              ),
              if (_localPath.isNotEmpty)
                _buildOption(
                  icon: Icons.copy_outlined,
                  text: 'Copy file path',
                  textColor: textColor,
                  onTap: () => _copyToClipboard(_localPath, 'File path'),
                ),
              _buildOption(
                icon: Icons.edit,
                text: 'edit_metadata'.tr(),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          MetadataEditorScreen(song: widget.song),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppDimens.spacingLg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color textColor, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.paddingLg),
      child: Column(
        children: [
          Container(
            width: AppDimens.dragHandleWidth,
            height: AppDimens.dragHandleHeight,
            margin: const EdgeInsets.only(bottom: AppDimens.paddingLg),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppDimens.radiusXxs),
            ),
          ),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                child: _artwork != null
                    ? Image.memory(
                        _artwork!,
                        width: AppDimens.thumbnailDefault,
                        height: AppDimens.thumbnailDefault,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholderArt(isDarkMode),
                      )
                    : _placeholderArt(isDarkMode),
              ),
              const SizedBox(width: AppDimens.spacingLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: AppTextStyles.subtitle(
                        isDarkMode: isDarkMode,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _artist,
                      style: AppTextStyles.bodyMd(
                        isDarkMode: isDarkMode,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholderArt(bool isDarkMode) {
    return Container(
      width: AppDimens.thumbnailDefault,
      height: AppDimens.thumbnailDefault,
      color: isDarkMode ? Colors.grey[850] : Colors.grey[300],
      child: Icon(
        Icons.music_note_rounded,
        color: MainScreenColors.getTextColor(
          isDarkMode,
        ).withValues(alpha: 0.22),
      ),
    );
  }

  Widget _buildOpenInOptions(Color textColor, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingLg,
        vertical: AppDimens.spacingXxs,
      ),
      child: Row(
        children: [
          Icon(Icons.open_in_new, color: textColor, size: AppDimens.iconLg),
          const SizedBox(width: AppDimens.spacingSm),
          Text(
            'open_in'.tr(),
            style: AppTextStyles.bodyMd(
              isDarkMode: isDarkMode,
              color: textColor,
            ),
          ),
          const SizedBox(width: AppDimens.spacingLg),
          const Spacer(),
          IconButton(
            icon: Container(
              width: AppDimens.iconXl,
              height: AppDimens.iconXl,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(AppDimens.radiusXs),
              ),
              child: const Icon(
                Icons.search,
                color: Colors.white,
                size: AppDimens.iconMd,
              ),
            ),
            onPressed: () => _openUrl(_youtubeSearchLink),
            tooltip: 'open_in_youtube'.tr(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: AppDimens.spacingLg),
          IconButton(
            icon: Icon(
              Icons.play_circle_outline,
              color: Colors.red[700],
              size: AppDimens.iconXl,
            ),
            onPressed: () => _openUrl(_youtubeMusicSearchLink),
            tooltip: 'open_in_youtube_music'.tr(),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: textColor ?? Colors.white),
      title: Text(
        text,
        style: AppTextStyles.bodyLg(
          isDarkMode: widget.isDarkMode,
          color: textColor ?? Colors.white,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingLg,
      ),
    );
  }
}
