import 'package:flutter/material.dart';

class PlayerScreen extends StatefulWidget {
  final String title;
  final String artist;
  final String imageUrl;

  const PlayerScreen({
    super.key,
    this.title = 'Blinding Lights',
    this.artist = 'The Weeknd',
    this.imageUrl =
        'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500',
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _isPlaying = true;
  bool _isLiked = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF140D21),
      body: Stack(
        children: [
          // Ambient Background Glow
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF533385).withValues(alpha: 0.6),
                    const Color(0xFF140D21),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHeaderIcon(Icons.chevron_left_rounded, () {
                        Navigator.pop(context);
                      }),
                      const Text(
                        'Now Playing',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _buildHeaderIcon(Icons.ios_share_rounded, () {}),
                    ],
                  ),
                ),

                const Spacer(),

                // Carousel Artwork Effect
                SizedBox(
                  height: 300,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Left Peeking Artwork
                      Positioned(
                        left: -60,
                        child: Opacity(
                          opacity: 0.4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.network(
                              'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300',
                              width: 120,
                              height: 240,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),

                      // Right Peeking Artwork
                      Positioned(
                        right: -60,
                        child: Opacity(
                          opacity: 0.4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.network(
                              'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
                              width: 120,
                              height: 240,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),

                      // Center Active Album Cover
                      Container(
                        width: 270,
                        height: 270,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(widget.imageUrl, fit: BoxFit.cover),
                              // Neon Overlay Text Effect
                              Center(
                                child: Text(
                                  widget.title.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                    shadows: [
                                      Shadow(
                                        color: Color(0xFFC042FF),
                                        blurRadius: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Track Details Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.artist,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _isLiked
                              ? const Color(0xFFC042FF)
                              : Colors.white.withValues(alpha: 0.7),
                          size: 26,
                        ),
                        onPressed: () => setState(() => _isLiked = !_isLiked),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Audio Waveform Visualizer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 36,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(35, (index) {
                            final heights = [
                              12,
                              18,
                              28,
                              14,
                              22,
                              32,
                              10,
                              24,
                              36,
                              18,
                              12,
                              26,
                              30,
                              16,
                              20,
                              28,
                              14,
                              34,
                              18,
                              22,
                              12,
                              26,
                              30,
                              16,
                              20,
                              28,
                              14,
                              22,
                              10,
                              18,
                              12,
                              24,
                              16,
                              10,
                              14,
                            ];
                            final isActive = index < 14;
                            return Container(
                              width: 3,
                              height: heights[index % heights.length]
                                  .toDouble(),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '1:27',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '2:59',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Playback Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.repeat_rounded,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 22,
                        ),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: () {},
                      ),

                      // Play/Pause Outline Circle
                      GestureDetector(
                        onTap: () => setState(() => _isPlaying = !_isPlaying),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          child: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),

                      IconButton(
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.playlist_play_rounded,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 26,
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, VoidCallback onTap) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white, size: 22),
        onPressed: onTap,
      ),
    );
  }
}
