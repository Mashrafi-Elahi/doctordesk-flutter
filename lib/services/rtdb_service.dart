import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Firebase Realtime Database Service for DoctorDesk Ratings & Reviews.
/// Stores and retrieves ratings directly to/from Firebase Realtime Database:
/// https://docdesk-1e4cc-default-rtdb.asia-southeast1.firebasedatabase.app
class RtdbService {
  static const String databaseUrl =
      'https://docdesk-1e4cc-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String databaseKey = 'ysEsUlQ6QWDywxVdst6aGbJVy4PHaOsIrRCxaSnS';

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _sanitizeKey(String raw) {
    return raw.replaceAll(RegExp(r'[\.\#\$\[\]]'), '_');
  }

  /// Submits a rating to Firebase Realtime Database under `/ratings/{doctorId}/{userId}`.
  /// Any account (patient, operator, doctor rating other doctors) can rate.
  /// Guests are not allowed to submit ratings.
  static Future<Map<String, dynamic>> submitRating({
    required String doctorId,
    required String userId,
    required int rating,
    String comment = '',
    String? proofImageUrl,
    String? raterRole,
    String? raterName,
  }) async {
    // Disallow guests from rating
    if (!AuthService.isSignedIn || AuthService.isGuest) {
      throw Exception('Guests cannot submit ratings. Please sign in to rate.');
    }

    final cleanDocId = _sanitizeKey(doctorId);
    final cleanUid = _sanitizeKey(userId);

    final resolvedRole = raterRole ??
        (AuthService.userRoles.isDoctor
            ? 'doctor'
            : (AuthService.userRoles.isOperator ? 'operator' : 'patient'));

    final resolvedName = raterName ??
        (AuthService.currentUser?.displayName?.isNotEmpty == true
            ? AuthService.currentUser!.displayName!
            : (resolvedRole == 'doctor'
                ? 'Doctor Specialist'
                : (resolvedRole == 'operator' ? 'Desk Operator' : 'Verified Patient')));

    final nowIso = DateTime.now().toIso8601String();
    final reviewData = {
      'doctorId': doctorId,
      'userId': userId,
      'patientUid': userId,
      'raterRole': resolvedRole,
      'raterName': resolvedName,
      'rating': rating,
      'comment': comment,
      'proofImageUrl': proofImageUrl ?? '',
      'isProofVerified': proofImageUrl != null && proofImageUrl.isNotEmpty,
      'createdAt': nowIso,
    };

    // 1. Write rating entry to Realtime Database: /ratings/{doctorId}/{userId}.json
    final reviewUrl = Uri.parse('$databaseUrl/ratings/$cleanDocId/$cleanUid.json?auth=$databaseKey');
    final response = await http.put(
      reviewUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(reviewData),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to record rating in Realtime Database: ${response.body}');
    }

    // 2. Fetch all ratings for this doctor from RTDB to compute accurate aggregate
    try {
      final allRatingsUrl = Uri.parse('$databaseUrl/ratings/$cleanDocId.json?auth=$databaseKey');
      final allRes = await http.get(allRatingsUrl);
      if (allRes.statusCode == 200 && allRes.body != 'null') {
        final Map<String, dynamic> allRatings =
            Map<String, dynamic>.from(jsonDecode(allRes.body) as Map);

        int count = 0;
        double totalWeightedScore = 0.0;

        for (final entry in allRatings.values) {
          if (entry is Map) {
            final num rScore = (entry['rating'] as num?) ?? 0;
            final hasProof = entry['proofImageUrl'] != null &&
                entry['proofImageUrl'].toString().isNotEmpty;
            final weight = hasProof ? 2 : 1;
            count += weight;
            totalWeightedScore += (rScore * weight);
          }
        }

        final double newAvg = count > 0
            ? double.parse((totalWeightedScore / count).toStringAsFixed(2))
            : rating.toDouble();

        // Save aggregate in Realtime Database: /ratings_aggregates/{doctorId}.json
        final aggUrl =
            Uri.parse('$databaseUrl/ratings_aggregates/$cleanDocId.json?auth=$databaseKey');
        await http.put(
          aggUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'doctorId': doctorId,
            'ratingCount': count,
            'ratingAverage': newAvg,
            'lastUpdated': nowIso,
          }),
        );

        // Also sync aggregate to Firestore doctor document for seamless offline/directory listings
        try {
          final doctorDocRef = _db.collection('doctors').doc(doctorId);
          final docSnap = await doctorDocRef.get();
          if (docSnap.exists) {
            await doctorDocRef.update({
              'ratingCount': count,
              'ratingAverage': newAvg,
            });
          }
        } catch (fsErr) {
          debugPrint('Firestore doctor aggregate sync notice: $fsErr');
        }
      }
    } catch (aggErr) {
      debugPrint('Realtime Database rating aggregation notice: $aggErr');
    }

    return reviewData;
  }

  /// Fetches reviews/ratings for a doctor from Firebase Realtime Database.
  /// Falls back to Firestore reviews if Realtime Database is empty.
  static Future<List<Map<String, dynamic>>> fetchDoctorRatings(String doctorId) async {
    final cleanDocId = _sanitizeKey(doctorId);

    try {
      final ratingsUrl = Uri.parse('$databaseUrl/ratings/$cleanDocId.json?auth=$databaseKey');
      final res = await http.get(ratingsUrl).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && res.body != 'null') {
        final Map<String, dynamic> rawMap =
            Map<String, dynamic>.from(jsonDecode(res.body) as Map);

        final List<Map<String, dynamic>> list = [];
        rawMap.forEach((key, val) {
          if (val is Map) {
            final map = Map<String, dynamic>.from(val);
            map['id'] = key;
            list.add(map);
          }
        });

        // Sort descending by createdAt
        list.sort((a, b) {
          final aDate = a['createdAt']?.toString() ?? '';
          final bDate = b['createdAt']?.toString() ?? '';
          return bDate.compareTo(aDate);
        });

        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('RtdbService.fetchDoctorRatings error: $e');
    }

    // Fallback to Firestore reviews
    try {
      final snap = await _db
          .collection('reviews')
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        final ts = data['createdAt'];
        if (ts is Timestamp) {
          data['createdAt'] = ts.toDate().toIso8601String();
        }
        return data;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Evaluates whether the user can rate this doctor:
  /// - Guest: Cannot rate (only checking allowed).
  /// - Doctor: Can rate other doctors, but NOT himself.
  /// - Operator & Patient: Can rate.
  /// - User who already rated this doctor: Cannot submit a duplicate rating.
  static Future<({bool canRate, String? message})> checkRatingEligibility({
    required String doctorId,
    required String? userId,
    Map<String, dynamic>? doctorData,
  }) async {
    // 1. Guests are not allowed to rate
    if (userId == null || !AuthService.isSignedIn || AuthService.isGuest) {
      return (
        canRate: false,
        message: 'Guests can only check ratings. Please sign in as a Patient, Operator, or Doctor to rate.',
      );
    }

    // 2. Doctor rating self check
    final isDoctor = AuthService.userRoles.isDoctor;
    if (isDoctor) {
      // Check if viewing own profile
      final claimedByUid = doctorData?['claimedByUid'];
      final doctorProfileId = doctorData?['_id'] ?? doctorData?['id'] ?? doctorId;

      final isDemoSelf = (AuthService.currentUser?.email == 'demo@mail.com' &&
          (doctorId == 'doctor_1' || doctorId == '1'));

      final isClaimedByMe = (claimedByUid != null && claimedByUid == userId);
      final isDirectMatch = (doctorId == userId || doctorProfileId == userId);

      if (isDemoSelf || isClaimedByMe || isDirectMatch) {
        return (
          canRate: false,
          message: 'Doctors cannot rate their own profile. You can rate other doctors.',
        );
      }
    }

    // 3. Prevent duplicate rating by the same user on this doctor in RTDB
    try {
      final cleanDocId = _sanitizeKey(doctorId);
      final cleanUid = _sanitizeKey(userId);
      final checkUrl =
          Uri.parse('$databaseUrl/ratings/$cleanDocId/$cleanUid.json?auth=$databaseKey');
      final res = await http.get(checkUrl).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200 && res.body != 'null') {
        return (
          canRate: false,
          message: 'You have already submitted a rating for this doctor.',
        );
      }
    } catch (_) {}

    return (canRate: true, message: null);
  }
}
