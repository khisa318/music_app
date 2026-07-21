import 'package:flutter/material.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music, size: 64, color: Color(0xFF1DB954)),
          SizedBox(height: 12),
          Text(
            'Your Library',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          SizedBox(height: 6),
          Text(
            'Playlists, Liked Songs & Local Music',
            style: TextStyle(color: Color(0xFFB3B3B3)),
          ),
        ],
      ),
    );
  }
}
