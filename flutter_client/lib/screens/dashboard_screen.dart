import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  final String abhaId;

  const DashboardScreen({super.key, required this.abhaId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
      ),
      body: Center(
        child: Text('Dashboard for ABHA: $abhaId\n\n(Timeline coming next)'),
      ),
    );
  }
}
