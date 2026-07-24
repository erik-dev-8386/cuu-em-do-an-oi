import 'package:flutter/material.dart';
// Đã dùng import package chuẩn tại đây:
import 'package:thanhdthaichink/services/nail_snapshot_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nailify AR Try-On',
      home: const NailSnapshotPage(),
    );
  }
}
