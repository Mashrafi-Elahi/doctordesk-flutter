import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/doctor.dart';

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.10.84:5000/api/v1',
  );

  static Future<Map<String, dynamic>> fetchDoctors({
    int page = 1,
    int limit = 20,
    String? search,
    String? speciality,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (speciality != null && speciality.isNotEmpty && speciality != 'All') {
      queryParams['speciality'] = speciality;
    }

    final uri = Uri.parse('$baseUrl/doctors').replace(queryParameters: queryParams);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == true) {
        final List data = jsonResponse['data'];
        final doctors = data.map((json) => Doctor.fromJson(json)).toList();
        return {
          'doctors': doctors,
          'total': jsonResponse['total'],
          'totalPages': jsonResponse['totalPages'],
        };
      }
    }
    throw Exception('Failed to load doctors');
  }

  static Future<Doctor> fetchDoctorById(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/doctors/$id'));

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == true) {
        return Doctor.fromJson(jsonResponse['data']);
      }
    }
    throw Exception('Failed to load doctor details');
  }

  static Future<List<Map<String, dynamic>>> fetchSpecialities() async {
    final response = await http.get(Uri.parse('$baseUrl/doctors/specialities'));

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == true) {
        final List data = jsonResponse['data'];
        return data.cast<Map<String, dynamic>>();
      }
    }
    throw Exception('Failed to load specialities');
  }

  static Future<List<Doctor>> fetchNearbyDoctors({
    required double lat,
    required double lng,
    int radiusKm = 10,
    String? speciality,
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String, String>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radiusKm': radiusKm.toString(),
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (speciality != null && speciality.isNotEmpty && speciality != 'All') {
      queryParams['speciality'] = speciality;
    }

    final uri = Uri.parse('$baseUrl/doctors/nearby').replace(queryParameters: queryParams);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == true) {
        final List data = jsonResponse['data'];
        return data.map((json) => Doctor.fromJson(json)).toList();
      }
    }
    throw Exception('Failed to load nearby doctors');
  }

  static Future<List<Map<String, dynamic>>> fetchGeocodeSuggestions(String query) async {
    final uri = Uri.parse('$baseUrl/geocode/suggest').replace(queryParameters: {'q': query});
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == true) {
        final List data = jsonResponse['data'];
        return data.cast<Map<String, dynamic>>();
      }
    }
    throw Exception('Failed to load geocode suggestions');
  }

  static Future<Map<String, dynamic>?> fetchTodayFeeling() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/journal/today'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          return jsonResponse['data'];
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> logFeeling({
    required String feeling,
    String? note,
    String? gratitudeText,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/journal'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'feeling': feeling,
              'note': note ?? '',
              'gratitudeText': gratitudeText ?? '',
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  static Future<List<Map<String, dynamic>>> fetchJournalEntries() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/journal'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          final List data = jsonResponse['data'];
          return data.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }
}

