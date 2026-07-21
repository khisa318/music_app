import 'package:flutter/material.dart';
import '../widgets/home_widgets.dart';

// --- YOUR SCREEN IMPORTS ---
// (Adjust filenames below if yours are named slightly differently)
import 'library_screen.dart';
import 'downloader_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF140D21),
      body: Stack(
        children: [
          // IndexedStack holding all 4 screens in exact order (indices 0, 1, 2, 3)
          IndexedStack(
            index: _currentNavIndex,
            children: [
              _buildHomeContent(), // Index 0: Home Page
              const LibraryScreen(), // Index 1: Library Page
              const DownloadsScreen(), // Index 2: Downloads Page
              const ProfileScreen(), // Index 3: Profile Page
            ],
          ),

          // Floating Navigation Dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavDock(
              selectedIndex: _currentNavIndex,
              onItemTapped: (index) {
                setState(() {
                  _currentNavIndex = index;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- HOME PAGE CONTENT ---
  Widget _buildHomeContent() {
    return Stack(
      children: [
        // Background Glow Effect
        Positioned(
          top: -50,
          left: -50,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFC042FF).withValues(alpha: 0.25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC042FF).withValues(alpha: 0.25),
                  blurRadius: 100,
                  spreadRadius: 50,
                ),
              ],
            ),
          ),
        ),

        // Scrollable Body
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TopHeader(),
                const SizedBox(height: 24),
                const FilterPills(),
                const SizedBox(height: 28),
                const Text(
                  'For you',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const ForYouCarousel(),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Popular',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        'Show all >',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const PopularTrackItem(
                  title: 'Blinding Lights',
                  subtitle: 'Top Hit',
                  imageUrl:
                      'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=200',
                ),
                const PopularTrackItem(
                  title: 'Save Your Tears',
                  subtitle: 'Soft Vibe',
                  imageUrl:
                      'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200',
                ),
                const PopularTrackItem(
                  title: 'Starboy',
                  subtitle: 'Fan Fav',
                  imageUrl:
                      'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200',
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
