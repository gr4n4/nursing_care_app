import 'package:flutter/material.dart';
import 'pages/io_balance_page.dart';

void main() {
  runApp(const CareIoApp());
}

class CareIoApp extends StatelessWidget {
  const CareIoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: IoBalancePage(),
    );
  }
}