import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for System UI control
import 'theme.dart';
import 'screens/discovery_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Polished UI: Setting the System Overlay style to match the new theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // Makes status bar transparent for a modern look
    statusBarIconBrightness: Brightness.light, // White icons for the Indigo AppBar
    systemNavigationBarColor: NexusTheme.backgroundLight, // Matches bottom bar to app background
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Locking orientation for a consistent professional feel
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const NexusApp());
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project Nexus',
      // UI: Applying your high-end NexusTheme
      theme: NexusTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      
      // The logic remains untouched, directing to your DiscoveryScreen
      home: const DiscoveryScreen(),
    );
  }
}