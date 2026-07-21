import 'dart:ui';
import 'package:flutter/material.dart';

// --- FLOATING NAV DOCK ---
class FloatingNavDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;

  const FloatingNavDock({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, Icons.home_outlined),
                _buildNavItem(
                  1,
                  Icons.library_music_rounded,
                  Icons.library_music_outlined,
                ),
                _buildNavItem(
                  2,
                  Icons.download_rounded,
                  Icons.download_outlined,
                ),
                _buildNavItem(
                  3,
                  Icons.person_rounded,
                  Icons.person_outline_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC042FF) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSelected ? activeIcon : inactiveIcon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

// --- TOP HEADER ---
class TopHeader extends StatelessWidget {
  const TopHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 20,
          backgroundImage: NetworkImage(
            'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100',
          ),
        ),
        const Spacer(),
        _buildCircleIconButton(Icons.search_rounded, () {}),
        const SizedBox(width: 10),
        _buildCircleIconButton(Icons.notifications_none_rounded, () {}),
      ],
    );
  }

  Widget _buildCircleIconButton(IconData icon, VoidCallback onTap) {
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
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }
}

// --- FILTER PILLS ---
class FilterPills extends StatefulWidget {
  const FilterPills({super.key});

  @override
  State<FilterPills> createState() => _FilterPillsState();
}

class _FilterPillsState extends State<FilterPills> {
  int _selectedIndex = 0;
  final List<String> _options = const ['All', 'Music', 'Podcasts', 'Live'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _options.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFC042FF)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFC042FF)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Center(
                child: Text(
                  _options[index],
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- FOR YOU CAROUSEL ---
class ForYouCarousel extends StatelessWidget {
  const ForYouCarousel({super.key});

  final List<Map<String, String>> _items = const [
    {
      'title': 'Starboy',
      'artist': 'The Weeknd',
      'image':
          'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
    },
    {
      'title': 'Midnight City',
      'artist': 'M83',
      'image':
          'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300',
    },
    {
      'title': 'Nightcall',
      'artist': 'Kavinsky',
      'image':
          'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    item['image']!,
                    width: 140,
                    height: 130,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item['title']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item['artist']!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- POPULAR TRACK ITEM ---
class PopularTrackItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;

  const PopularTrackItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Colors.white54,
                size: 20,
              ),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
