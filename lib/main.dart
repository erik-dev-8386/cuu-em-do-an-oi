import 'package:flutter/material.dart';
import 'snapshot/nail_snapshot_page.dart';
import 'ar/ar_camera_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NailifyApp());
}

class NailifyApp extends StatelessWidget {
  const NailifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nailify - Virtual & AR Try-On',
      theme: ThemeData(
        primarySwatch: Colors.pink,
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};

  Widget _buildTab(int index) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }

    return switch (index) {
      0 => const NailSnapshotPage(),
      1 => const ArCameraPage(),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(2, _buildTab),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFFFF4081),
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() {
          _currentIndex = index;
          _visitedTabs.add(index);
        }),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library),
            label: 'Snapshot Try-On',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera),
            label: 'Realtime AR',
          ),
        ],
      ),
    );
  }
}
