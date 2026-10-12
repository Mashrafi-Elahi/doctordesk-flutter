import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Read-only place search for the Nearby Doctors location picker.
/// Area coordinates in `assets/dhaka_places.json` are approximate centers.
class LocationSearchService {
  LocationSearchService._();

  static const _assetPath = 'assets/dhaka_places.json';
  static List<Map<String, dynamic>>? _dhakaPlaces;
  static List<Map<String, dynamic>> _chambers = const [];
  static DateTime? _lastNominatimRequest;

  static Future<void> initialize() async {
    await _loadDhakaPlaces();
    await _loadChambers();
  }

  static Future<List<Map<String, dynamic>>> localSuggestions(
      String query) async {
    final normalized = _normalize(query);
    if (normalized.length < 2) return const [];
    final places = await _loadDhakaPlaces();
    return _sortAndFilter([...places, ..._chambers], normalized);
  }

  static Future<List<Map<String, dynamic>>> photonSuggestions(
      String query) async {
    final uri = Uri.https('photon.komoot.io', '/api', {
      'q': query,
      'limit': '8',
      'lat': '23.78',
      'lon': '90.41',
      'bbox': '90.25,23.62,90.55,23.95',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 4));
    debugPrint('Photon suggestion status: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw StateError('Photon returned HTTP ${response.statusCode}.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (body['features'] as List? ?? const []);
    return features
        .map<Map<String, dynamic>?>((feature) {
          final data = feature as Map<String, dynamic>;
          final properties =
              (data['properties'] as Map?)?.cast<String, dynamic>();
          final geometry = (data['geometry'] as Map?)?.cast<String, dynamic>();
          final coordinates = geometry?['coordinates'] as List?;
          if (properties == null ||
              coordinates == null ||
              coordinates.length < 2) {
            return null;
          }
          final lng = (coordinates[0] as num?)?.toDouble();
          final lat = (coordinates[1] as num?)?.toDouble();
          final name = properties['name']?.toString().trim();
          if (lat == null || lng == null || name == null || name.isEmpty) {
            return null;
          }
          final detail = [
            properties['district'] ?? properties['suburb'],
            properties['city'],
          ]
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty);
          final displayParts = <String>{name, ...detail};
          return {
            'name': name,
            'displayName': displayParts.join(', '),
            'lat': lat,
            'lng': lng,
            'source': 'Photon',
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Nominatim is deliberately reserved for full/exact address searches.
  static bool looksLikeExactAddress(String query) =>
      _looksLikeExactAddress(query);

  static Future<List<Map<String, dynamic>>> nominatimExactAddress(
      String query) async {
    if (!_looksLikeExactAddress(query)) return const [];

    final now = DateTime.now();
    final previous = _lastNominatimRequest;
    if (previous != null) {
      final elapsed = now.difference(previous);
      if (elapsed < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
      }
    }
    _lastNominatimRequest = DateTime.now();

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '5',
      'countrycodes': 'bd',
    });
    final response = await http.get(uri, headers: const {
      'User-Agent':
          'DoctorDesk-Flutter/1.0 (student project contact: dev@doctordesk.bd)',
    }).timeout(const Duration(seconds: 4));
    debugPrint('Nominatim suggestion status: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw StateError('Nominatim returned HTTP ${response.statusCode}.');
    }

    final rows = jsonDecode(response.body) as List;
    return rows
        .map<Map<String, dynamic>>((item) {
          final data = item as Map<String, dynamic>;
          return {
            'name': data['display_name']?.toString() ?? '',
            'displayName': data['display_name']?.toString() ?? '',
            'lat': double.parse(data['lat'].toString()),
            'lng': double.parse(data['lon'].toString()),
            'source': 'Nominatim',
          };
        })
        .where((item) => (item['name'] as String).isNotEmpty)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> _loadDhakaPlaces() async {
    if (_dhakaPlaces != null) return _dhakaPlaces!;
    final decoded = jsonDecode(await rootBundle.loadString(_assetPath)) as List;
    _dhakaPlaces = decoded.map<Map<String, dynamic>>((item) {
      final data = (item as Map).cast<String, dynamic>();
      final name = data['name'].toString();
      return {
        ...data,
        'name': name,
        'displayName': '$name, Dhaka, Bangladesh',
        'source': 'Dhaka area (approximate center)',
      };
    }).toList(growable: false);
    return _dhakaPlaces!;
  }

  static Future<void> _loadChambers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('chambers')
        .limit(500)
        .get();
    _chambers = snapshot.docs
        .map((doc) => _chamberSuggestion(doc.data()))
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    debugPrint('Loaded ${_chambers.length} chamber/hospital search names.');
  }

  static Map<String, dynamic>? _chamberSuggestion(Map<String, dynamic> data) {
    final name = [
      data['hospitalName'],
      data['chamberName'],
      data['name'],
      data['hospital'],
    ].map((value) => value?.toString().trim()).firstWhere(
          (value) => value != null && value.isNotEmpty,
          orElse: () => null,
        );
    if (name == null) return null;

    final point = data['location'];
    final lat =
        _asDouble(data['lat']) ?? (point is GeoPoint ? point.latitude : null);
    final lng =
        _asDouble(data['lng']) ?? (point is GeoPoint ? point.longitude : null);
    if (lat == null || lng == null) return null;
    final area = data['area']?.toString().trim();
    return {
      'name': name,
      'displayName': area == null || area.isEmpty ? name : '$name, $area',
      'alt': [area ?? '', data['address']?.toString() ?? ''],
      'lat': lat,
      'lng': lng,
      'source': 'DoctorDesk chamber',
    };
  }

  static List<Map<String, dynamic>> _sortAndFilter(
      List<Map<String, dynamic>> values, String query) {
    final prefix = <Map<String, dynamic>>[];
    final contains = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final value in values) {
      final fields = <String>[
        value['name']?.toString() ?? '',
        value['bn']?.toString() ?? '',
        ...((value['alt'] as List?) ?? const []).map((item) => item.toString()),
      ].map(_normalize).where((field) => field.isNotEmpty).toList();
      final isPrefix = fields.any((field) => field.startsWith(query));
      final isContains = fields.any((field) => field.contains(query));
      if (!isPrefix && !isContains) continue;
      final key = _normalize(value['name']?.toString() ?? '');
      if (key.isEmpty || !seen.add(key)) continue;
      (isPrefix ? prefix : contains).add(value);
    }
    return [...prefix, ...contains];
  }

  static bool _looksLikeExactAddress(String query) {
    final trimmed = query.trim();
    return trimmed.contains(',') ||
        RegExp(r'\d').hasMatch(trimmed) ||
        trimmed.split(RegExp(r'\s+')).length >= 3;
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  static double? _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
