import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/doctor.dart';

class ApiService {
  static String? _resolvedBaseUrl;

  static List<String> get _candidateBaseUrls {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return [envUrl];
    }
    if (kIsWeb) {
      return [
        'http://localhost:5000/api/v1',
        'http://127.0.0.1:5000/api/v1',
        'http://192.168.10.84:5000/api/v1',
      ];
    }
    try {
      if (Platform.isAndroid) {
        return [
          'http://10.0.2.2:5000/api/v1',
          'http://192.168.10.84:5000/api/v1',
          'http://localhost:5000/api/v1',
        ];
      }
    } catch (_) {}
    return [
      'http://localhost:5000/api/v1',
      'http://127.0.0.1:5000/api/v1',
      'http://192.168.10.84:5000/api/v1',
    ];
  }

  static String get baseUrl {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;
    return _candidateBaseUrls.first;
  }

  static void setBaseUrl(String url) {
    _resolvedBaseUrl = url;
  }

  /// Sends a GET request with automatic fallback between local host, emulator loopback, and LAN IP
  static Future<http.Response> getRequest(String path) async {
    final candidates = [_resolvedBaseUrl, ..._candidateBaseUrls]
        .whereType<String>()
        .toSet()
        .toList();

    Exception? lastError;
    for (final base in candidates) {
      try {
        final uri = Uri.parse('$base$path');
        final res = await http.get(uri).timeout(const Duration(seconds: 4));
        _resolvedBaseUrl = base;
        return res;
      } catch (e) {
        lastError = Exception('No internet connection. Please check your network and try again.');
      }
    }
    throw lastError ?? Exception('No internet connection. Please check your network and try again.');
  }

  /// Sends a POST request with automatic fallback
  static Future<http.Response> postRequest(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final candidates = [_resolvedBaseUrl, ..._candidateBaseUrls]
        .whereType<String>()
        .toSet()
        .toList();

    Exception? lastError;
    for (final base in candidates) {
      try {
        final uri = Uri.parse('$base$path');
        final res = await http
            .post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 5));
        _resolvedBaseUrl = base;
        return res;
      } catch (e) {
        lastError = Exception('No internet connection. Please check your network and try again.');
      }
    }
    throw lastError ?? Exception('No internet connection. Please check your network and try again.');
  }

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

    try {
      final query = Uri(queryParameters: queryParams).query;
      final response = await getRequest('/doctors?$query');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          final List data = jsonResponse['data'];
          final doctors = data.map((json) => Doctor.fromJson(json)).toList();

          // Preload and cache real doctor data for offline resilience
          if (page == 1 && (search == null || search.isEmpty) && (speciality == null || speciality == 'All')) {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('cached_doctors_data', jsonEncode(data));
              await prefs.setInt('cached_doctors_total', (jsonResponse['total'] as int?) ?? doctors.length);
            } catch (_) {}
          }

          return {
            'doctors': doctors,
            'total': jsonResponse['total'],
            'totalPages': jsonResponse['totalPages'],
            'isOffline': false,
          };
        }
      }
    } catch (e) {
      // Offline fallback: load preloaded real doctor directory from cache
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawCached = prefs.getString('cached_doctors_data');
        if (rawCached != null && rawCached.isNotEmpty) {
          final List rawList = jsonDecode(rawCached);
          List<Doctor> docs = rawList.map((j) => Doctor.fromJson(j)).toList();

          if (speciality != null && speciality.isNotEmpty && speciality != 'All') {
            docs = docs.where((d) => d.specialities.any((s) => s.toLowerCase() == speciality.toLowerCase())).toList();
          }
          if (search != null && search.trim().isNotEmpty) {
            final q = search.trim().toLowerCase();
            docs = docs.where((d) =>
              d.name.toLowerCase().contains(q) ||
              d.specialities.any((s) => s.toLowerCase().contains(q)) ||
              (d.designation != null && d.designation!.toLowerCase().contains(q))
            ).toList();
          }

          return {
            'doctors': docs,
            'total': docs.length,
            'totalPages': 1,
            'isOffline': true,
          };
        }
      } catch (_) {}

      throw Exception('No internet connection. Please check your network and try again.');
    }

    throw Exception('Failed to load doctors');
  }

  static Future<Doctor> fetchDoctorById(String id) async {
    try {
      final response = await getRequest('/doctors/$id');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          return Doctor.fromJson(jsonResponse['data']);
        }
      }
    } catch (_) {
      // Offline fallback: locate doctor in cached directory
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawCached = prefs.getString('cached_doctors_data');
        if (rawCached != null) {
          final List rawList = jsonDecode(rawCached);
          final match = rawList.firstWhere(
            (j) => j['_id'] == id || j['id'] == id,
            orElse: () => null,
          );
          if (match != null) {
            return Doctor.fromJson(match);
          }
        }
      } catch (_) {}
      throw Exception('No internet connection. Please check your network and try again.');
    }
    throw Exception('Failed to load doctor details');
  }

  static Future<List<Map<String, dynamic>>> fetchSpecialities() async {
    try {
      final response = await getRequest('/doctors/specialities');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          final List data = jsonResponse['data'];
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_specialities_data', jsonEncode(data));
          } catch (_) {}
          return data.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {
      // Offline fallback: return cached specialities
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('cached_specialities_data');
        if (raw != null) {
          final List data = jsonDecode(raw);
          return data.cast<Map<String, dynamic>>();
        }
      } catch (_) {}
      throw Exception('No internet connection. Please check your network and try again.');
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

    final query = Uri(queryParameters: queryParams).query;
    final response = await getRequest('/doctors/nearby?$query');

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
    final queryString = Uri(queryParameters: {'q': query}).query;
    final response = await getRequest('/geocode/suggest?$queryString');

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
      final response = await getRequest('/journal/today');
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
      final response = await postRequest(
        '/journal',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'feeling': feeling,
          'note': note ?? '',
          'gratitudeText': gratitudeText ?? '',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  static Future<List<Map<String, dynamic>>> fetchJournalEntries() async {
    try {
      final response = await getRequest('/journal');

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

  /// GET /api/v1/doctors/:id/reviews
  static Future<List<Map<String, dynamic>>> fetchReviews(
      String doctorId) async {
    final response = await getRequest('/doctors/$doctorId/reviews');

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      if (jsonResponse['success'] == true) {
        final List data = jsonResponse['data'] as List;
        return data.cast<Map<String, dynamic>>();
      }
      throw Exception(
          'fetchReviews: unexpected response — ${response.body}');
    }
    throw Exception(
        'fetchReviews: HTTP ${response.statusCode} — ${response.reasonPhrase}');
  }

  /// POST /api/v1/doctors/:id/reviews
  static Future<Map<String, dynamic>> submitReview(
    String doctorId, {
    required String patientUid,
    required int rating,
    String comment = '',
    String? proofImageUrl,
  }) async {
    final body = <String, dynamic>{
      'patientUid': patientUid,
      'rating': rating,
      'comment': comment,
    };
    if (proofImageUrl != null && proofImageUrl.isNotEmpty) {
      body['proofImageUrl'] = proofImageUrl;
    }

    final response = await postRequest(
      '/doctors/$doctorId/reviews',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      if (jsonResponse['success'] == true) {
        return jsonResponse['data'] as Map<String, dynamic>;
      }
      throw Exception(
          'submitReview: unexpected response — ${response.body}');
    }
    throw Exception(
        'submitReview: HTTP ${response.statusCode} — ${response.reasonPhrase}');
  }

  /// POST /api/v1/doctors/:id/claim
  static Future<Map<String, dynamic>> claimDoctor(
    String doctorId, {
    required String bmdcRegNumber,
    required String claimedByUid,
    String? certificateImageUrl,
  }) async {
    final body = <String, dynamic>{
      'bmdcRegNumber': bmdcRegNumber,
      'claimedByUid': claimedByUid,
    };
    if (certificateImageUrl != null && certificateImageUrl.isNotEmpty) {
      body['certificateImageUrl'] = certificateImageUrl;
    }

    final response = await postRequest(
      '/doctors/$doctorId/claim',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      if (jsonResponse['success'] == true) {
        return jsonResponse['data'] as Map<String, dynamic>;
      }
      throw Exception(
          'claimDoctor: unexpected response — ${response.body}');
    }
    throw Exception(
        'claimDoctor: HTTP ${response.statusCode} — ${response.reasonPhrase}');
  }

  /// POST /api/v1/specialty-feedback (Fire-and-forget)
  static Future<void> submitSpecialtyFeedback({
    required String inputText,
    required String matchedSpecialty,
    required String source, // 'rule_based' | 'gemini'
    required bool liked,
    String language = 'unknown',
  }) async {
    try {
      await postRequest(
        '/specialty-feedback',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'inputText': inputText,
          'matchedSpecialty': matchedSpecialty,
          'source': source,
          'liked': liked,
          'language': language,
        }),
      );
    } catch (_) {
      // Fire-and-forget by design — a failed feedback POST must never interrupt the user.
    }
  }

  /// GET /api/v1/users/:uid
  static Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    try {
      final response = await getRequest('/users/$uid');
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          return json['data'] as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return null;
  }

  /// POST /api/v1/users/sync
  static Future<Map<String, dynamic>?> syncUser({
    required String uid,
    String? email,
    String? name,
  }) async {
    try {
      final response = await postRequest(
        '/users/sync',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'email': email ?? '',
          'name': name ?? '',
        }),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          return json['data'] as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return null;
  }

  /// GET /api/v1/doctors/:id/can-review?patientUid=xxx
  static Future<bool> checkCanReview(String doctorId, String patientUid) async {
    try {
      final response = await getRequest('/doctors/$doctorId/can-review?patientUid=$patientUid');
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['canReview'] == true;
      }
    } catch (_) {}
    return true; // fallback to true if offline, backend will guard on submit
  }
}

