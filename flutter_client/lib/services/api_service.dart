import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Physical device on the same WiFi/hotspot as your PC
  // Android emulator → use 10.0.2.2:3000 instead
  static const String baseUrl = 'http://172.20.10.2:3000';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  static Future<Map<String, dynamic>> linkRecord(String abhaId, String name, String dob) async {
    final response = await http.post(
      Uri.parse('$baseUrl/link-record'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'abha_id': abhaId, 'name': name, 'dob': dob}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to link record: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(String abhaId, String otp) async {
    final response = await http.post(
      Uri.parse('$baseUrl/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'abha_id': abhaId, 'otp': otp}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['access_token'] != null) {
        await saveToken(data['access_token']);
      }
      return data;
    } else {
      throw Exception('Invalid OTP: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getPatientFHIR(String abhaId) async {
    final response = await http.get(Uri.parse('$baseUrl/patient/$abhaId'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch patient FHIR data: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getTimeline(String abhaId) async {
    final response = await http.get(Uri.parse('$baseUrl/patient/$abhaId/timeline'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch timeline: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> searchTimeline(String abhaId, String query) async {
    final response = await http.post(
      Uri.parse('$baseUrl/patient/$abhaId/search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to search timeline: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> scanReport(String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/scan-report'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to process report: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> generateQr(Map<String, dynamic> patientData) async {
    final response = await http.post(
      Uri.parse('$baseUrl/generate-qr'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'data': patientData}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to generate QR: ${response.body}');
    }
  }
}
