import 'package:flutter/material.dart';
import 'package:music_app/screens/home_screen.dart';

void main() {
  runApp(const MusiXApp());
}

class MusiXApp extends StatelessWidget {
  const MusiXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'musiX',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(
          0xFF140D21,
        ), // Purple-dark background
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
