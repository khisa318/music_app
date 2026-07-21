import 'package0:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFF1E1E1E),
            child: Icon(Icons.person, size: 48, color: Color(0xFF1DB954)),
          ),
          SizedBox(height: 16),
          Text(
            'User Profile',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          SizedBox(height: 6),
          Text(
            'Account Settings & Preferences',
            style: TextStyle(color: Color(0xFFB3B3B3)),
          ),
        ],
      ),
    );
  }
}
