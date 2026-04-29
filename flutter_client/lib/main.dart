import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/discovery_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusApp());
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project Nexus',
      theme: NexusTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const DiscoveryScreen(),
    );
  }
}
