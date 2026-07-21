import 'package:flutter/material.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedPillIndex = 0;
  final List<String> _pills = ['All', 'Liked Songs', 'Playlists', 'Downloads'];

  final List<Map<String, String>> _tracks = const [
    {
      'title': 'Save Your Tears',
      'artist': 'The Weeknd',
      'duration': '3:35',
      'image':
          'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200',
    },
    {
      'title': 'Happier Than Ever',
      'artist': 'Billie Eilish',
      'duration': '4:57',
      'image':
          'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=200',
    },
    {
      'title': 'Sunflower',
      'artist': 'Post Malone',
      'duration': '2:40',
      'image':
          'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200',
    },
    {
      'title': 'Believer',
      'artist': 'Imagine Dragons',
      'duration': '3:25',
      'image':
          'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=200',
    },
    {
      'title': 'Positions',
      'artist': 'Ariana Grande',
      'duration': '3:02',
      'image':
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200',
    },
    {
      'title': 'Shivers',
      'artist': 'Ed Sheeran',
      'duration': '3:28',
      'image':
          'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=200',
    },
    {
      'title': 'Ghost',
      'artist': 'Justin Bieber',
      'duration': '3:12',
      'image':
          'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=200',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF140D21),
      body: Stack(
        children: [
          // Background Purple Glow
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC042FF).withValues(alpha: 0.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFC042FF).withValues(alpha: 0.2),
                    blurRadius: 90,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header with Avatar & Icons
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 20,
                        backgroundImage: NetworkImage(
                          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100',
                        ),
                      ),
                      const Spacer(),
                      _buildCircleIconButton(Icons.search_rounded),
                      const SizedBox(width: 10),
                      _buildCircleIconButton(Icons.notifications_none_rounded),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Screen Title
                  const Text(
                    'Your library',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Filter Pills
                  SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pills.length,
                      itemBuilder: (context, index) {
                        final isSelected = _selectedPillIndex == index;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedPillIndex = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFC042FF)
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFC042FF)
                                    : Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _pills[index],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Songs List
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _tracks.length,
                    itemBuilder: (context, index) {
                      final track = _tracks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            // Track Artwork
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                track['image']!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 52,
                                  height: 52,
                                  color: Colors.white.withValues(alpha: 0.1),
                                  child: const Icon(
                                    Icons.music_note,
                                    color: Color(0xFFC042FF),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Track Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track['title']!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    track['artist']!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Duration
                            Text(
                              track['duration']!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Play Button
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 100), // Bottom clearance for dock
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleIconButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: () {},
      ),
    );
  }
}
