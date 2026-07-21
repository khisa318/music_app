import 'package:flutter/material.dart';

class DownloaderScreen extends StatelessWidget {
  const DownloaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Media Downloader',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste audio or video link to download locally',
            style: TextStyle(color: Color(0xFFB3B3B3)),
          ),
          const SizedBox(height: 20),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Paste URL here...',
              hintStyle: const TextStyle(color: Color(0xFFB3B3B3)),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.download, color: Colors.black),
              label: const Text(
                'Download Media',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
