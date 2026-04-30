import 'package:flutter/material.dart';

class NexusTheme {
  // Color: Navy Blue (Primary Brand from Design)
  static const Color primaryBlue = Color(0xFF0F2E4A); 
  
  // Color: Accent Gold (From Design)
  static const Color accentGold = Color(0xFFF5A623);  

  // Color: Success Green (For toggles and verified state)
  static const Color accentTeal = Color(0xFF10B981);  
  
  static const Color backgroundLight = Color(0xFFFAFAFA); // Off-white
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF1E293B);
  static const Color textLight = Color(0xFF64748B);
  static const Color errorRed = Color(0xFFEF4444);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto', 
      
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentTeal,
        surface: cardWhite,
        error: errorRed,
      ),
      scaffoldBackgroundColor: backgroundLight,
      
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue, 
        elevation: 0,
        centerTitle: true, 
        iconTheme: IconThemeData(color: Colors.white, size: 24),
        shape: Border(bottom: BorderSide(color: accentGold, width: 4)),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22, // Increased for standout presence
          fontWeight: FontWeight.w900, // Ultra-bold
          letterSpacing: 0.5,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0, // Flat design from mockup
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          // Logic: Dynamic shape prevents 'const' errors
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), // Pill-shaped like mockup
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: textLight, fontWeight: FontWeight.w500),
      ),

      cardTheme: CardThemeData(
        color: cardWhite,
        elevation: 0, // Flat cards with borders
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), // Softer corners
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1), // Light border
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: textDark, fontWeight: FontWeight.w900, letterSpacing: -1.5),
        headlineMedium: TextStyle(color: textDark, fontWeight: FontWeight.w800, fontSize: 28),
        titleLarge: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 22),
        bodyLarge: TextStyle(color: textDark, fontSize: 16, height: 1.6, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(color: textLight, fontSize: 14, fontWeight: FontWeight.w400),
      ),
    );
  }
}