import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/doctor.dart';
import 'geofire_utils.dart';
import 'rtdb_service.dart';

/// Cloud Firestore service providing complete data access for DoctorDesk.
/// Matches the method signatures of [ApiService] for transparent backend switching.
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache for cursor pagination: key -> Map<pageNumber, DocumentSnapshot>
  static final Map<String, Map<int, DocumentSnapshot>> _pageCursors = {};

  // =========================================================================
  // DOCTORS DIRECTORY & SEARCH
  // =========================================================================

  /// Fetches doctors with pagination, optional specialty filter, and prefix search.
  /// Matches ApiService.fetchDoctors signature.
  static Future<Map<String, dynamic>> fetchDoctors({
    int page = 1,
    int limit = 20,
    String? search,
    String? speciality,
  }) async {
    final queryKey = '${search ?? ""}_${speciality ?? ""}';

    try {
      Query<Map<String, dynamic>> query = _db.collection('doctors');

      // 1. Specialty filtering via array-contains
      if (speciality != null && speciality.isNotEmpty && speciality != 'All') {
        query = query.where('specialities', arrayContains: speciality);
      }

      // 2. Prefix search on lowercase name
      final trimmedSearch = search?.trim().toLowerCase();
      if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
        query = query
            .where('name_lower', isGreaterThanOrEqualTo: trimmedSearch)
            .where('name_lower', isLessThanOrEqualTo: '$trimmedSearch\uf8ff')
            .orderBy('name_lower');
      } else {
        // Default ordering when browsing: highest rating count first
        query = query.orderBy('ratingCount', descending: true);
      }

      // 3. Cursor-based pagination
      _pageCursors.putIfAbsent(queryKey, () => {});
      final cursors = _pageCursors[queryKey]!;

      if (page > 1 && cursors.containsKey(page - 1)) {
        final lastDoc = cursors[page - 1]!;
        query = query.startAfterDocument(lastDoc);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      final docs = snapshot.docs;

      if (docs.isNotEmpty) {
        cursors[page] = docs.last;
      }

      final doctors = docs.map((doc) {
        final data = doc.data();
        data['_id'] = doc.id;
        return Doctor.fromJson(data);
      }).toList();

      // Estimate or fetch total count
      int totalCount = doctors.length;
      try {
        if (speciality != null && speciality.isNotEmpty && speciality != 'All') {
          final countSnapshot = await _db
              .collection('doctors')
              .where('specialities', arrayContains: speciality)
              .count()
              .get();
          totalCount = countSnapshot.count ?? doctors.length;
        } else if (trimmedSearch == null || trimmedSearch.isEmpty) {
          final countSnapshot = await _db.collection('doctors').count().get();
          totalCount = countSnapshot.count ?? doctors.length;
        } else {
          totalCount = doctors.length >= limit ? page * limit + 1 : (page - 1) * limit + doctors.length;
        }
      } catch (_) {}

      final totalPages = (totalCount / limit).ceil().clamp(1, 9999);

      // Preload & cache for offline fallback
      if (page == 1 && (search == null || search.isEmpty) && (speciality == null || speciality == 'All')) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final rawList = docs.map((d) {
            final m = d.data();
            m['_id'] = d.id;
            return m;
          }).toList();
          await prefs.setString('cached_doctors_data', jsonEncode(rawList));
          await prefs.setInt('cached_doctors_total', totalCount);
        } catch (_) {}
      }

      return {
        'doctors': doctors,
        'total': totalCount,
        'totalPages': totalPages,
        'isOffline': false,
      };
    } catch (e) {
      debugPrint('Firestore fetchDoctors error: $e. Falling back to cache...');
      // Offline fallback: load cached doctors
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawCached = prefs.getString('cached_doctors_data');
        if (rawCached != null && rawCached.isNotEmpty) {
          final List rawList = jsonDecode(rawCached);
          List<Doctor> docs = rawList.map((j) => Doctor.fromJson(j)).toList();

          if (speciality != null && speciality.isNotEmpty && speciality != 'All') {
            docs = docs
                .where((d) => d.specialities.any((s) => s.toLowerCase() == speciality.toLowerCase()))
                .toList();
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
      throw Exception('Could not connect to database. Please check your internet connection.');
    }
  }

  /// Fetches a doctor by document ID.
  /// Also ensures all chamber locations are populated.
  static Future<Doctor> fetchDoctorById(String id) async {
    try {
      final docRef = _db.collection('doctors').doc(id);
      var snapshot = await docRef.get();

      if (!snapshot.exists && !id.startsWith('doctor_')) {
        snapshot = await _db.collection('doctors').doc('doctor_$id').get();
      }

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        data['_id'] = snapshot.id;

        // Query top-level chambers for any additional chambers added
        try {
          final chamberDocs = await _db
              .collection('chambers')
              .where('doctorId', isEqualTo: snapshot.id)
              .get();

          if (chamberDocs.docs.isNotEmpty) {
            final existingChambers = (data['chambers'] as List?) ?? [];
            final dynamicChambers = chamberDocs.docs.map((c) => c.data()).toList();
            data['chambers'] = [...existingChambers, ...dynamicChambers];
          }
        } catch (_) {}

        return Doctor.fromJson(data);
      }
    } catch (e) {
      debugPrint('Firestore fetchDoctorById error: $e');
    }

    // Offline cache lookup
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawCached = prefs.getString('cached_doctors_data');
      if (rawCached != null) {
        final List rawList = jsonDecode(rawCached);
        final match = rawList.firstWhere(
          (j) => j['_id'] == id || j['id'] == id || j['_id'] == 'doctor_$id',
          orElse: () => null,
        );
        if (match != null) {
          return Doctor.fromJson(match);
        }
      }
    } catch (_) {}

    throw Exception('Failed to load doctor profile');
  }

  /// Fetches precomputed specialities list and doctor counts from meta/specialities.
  static Future<List<Map<String, dynamic>>> fetchSpecialities() async {
    try {
      final snapshot = await _db.collection('meta').doc('specialities').get();
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        if (data['list'] is List) {
          final list = (data['list'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();

          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_specialities_data', jsonEncode(list));
          } catch (_) {}

          return list;
        }
      }
    } catch (e) {
      debugPrint('Firestore fetchSpecialities error: $e');
    }

    // Offline fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_specialities_data');
      if (raw != null) {
        final List data = jsonDecode(raw);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    return [];
  }

  /// Nearby doctors search:
  /// 1. Computes geohash bounds for radiusKm around (lat, lng)
  /// 2. Queries chambers collection for geohashes
  /// 3. Filters by exact Haversine distance
  /// 4. Fetches doctor profiles in chunks of 30 via whereIn
  /// 5. Sorts by distance and paginates
  static Future<List<Doctor>> fetchNearbyDoctors({
    required double lat,
    required double lng,
    int radiusKm = 10,
    String? speciality,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      // Compute geohash query bounds matching geofire-common exactly
      final bounds = GeofireUtils.geohashQueryBounds([lat, lng], radiusKm * 1000.0);

      // Query chambers collection across geohash bounds
      final List<Map<String, dynamic>> matchingChambers = [];

      final queryFutures = bounds.map((bound) {
        return _db
            .collection('chambers')
            .where('geohash', isGreaterThanOrEqualTo: bound[0])
            .where('geohash', isLessThanOrEqualTo: bound[1])
            .get();
      });

      final querySnapshots = await Future.wait(queryFutures);
      for (final snap in querySnapshots) {
        for (final doc in snap.docs) {
          final data = doc.data();
          final chLat = (data['lat'] as num?)?.toDouble();
          final chLng = (data['lng'] as num?)?.toDouble();

          if (chLat != null && chLng != null) {
            final distanceKm = GeofireUtils.distanceBetweenKm([lat, lng], [chLat, chLng]);
            if (distanceKm <= radiusKm) {
              data['distance'] = distanceKm;
              matchingChambers.add(data);
            }
          }
        }
      }

      if (matchingChambers.isEmpty) {
        return [];
      }

      // Sort chambers by distance
      matchingChambers.sort((a, b) =>
          ((a['distance'] as num?) ?? 999.0).compareTo((b['distance'] as num?) ?? 999.0));

      // Extract unique doctor IDs
      final Map<String, Map<String, dynamic>> doctorToChamberMap = {};
      for (final ch in matchingChambers) {
        final docId = ch['doctorId'] as String?;
        if (docId != null && !doctorToChamberMap.containsKey(docId)) {
          doctorToChamberMap[docId] = ch;
        }
      }

      final uniqueDoctorIds = doctorToChamberMap.keys.toList();
      if (uniqueDoctorIds.isEmpty) return [];

      // Fetch doctors in chunks of 30 (Firestore whereIn limit)
      final List<Doctor> doctors = [];
      const chunkSize = 30;

      for (int i = 0; i < uniqueDoctorIds.length; i += chunkSize) {
        final chunk = uniqueDoctorIds.sublist(
          i,
          (i + chunkSize > uniqueDoctorIds.length) ? uniqueDoctorIds.length : i + chunkSize,
        );

        final docSnap = await _db
            .collection('doctors')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in docSnap.docs) {
          final data = doc.data();
          data['_id'] = doc.id;
          final chamberData = doctorToChamberMap[doc.id];
          if (chamberData != null) {
            data['distance'] = chamberData['distance'];
            data['chamber'] = chamberData;
          }

          // Specialty filter check
          if (speciality != null && speciality.isNotEmpty && speciality != 'All') {
            final specs = (data['specialities'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
            if (!specs.contains(speciality.toLowerCase())) {
              continue;
            }
          }

          doctors.add(Doctor.fromJson(data));
        }
      }

      // Sort final doctors list by distance
      doctors.sort((a, b) => (a.distance ?? 999.0).compareTo(b.distance ?? 999.0));

      // Pagination slice
      final startIndex = (page - 1) * limit;
      if (startIndex >= doctors.length) return [];
      final endIndex = (startIndex + limit > doctors.length) ? doctors.length : startIndex + limit;

      return doctors.sublist(startIndex, endIndex);
    } catch (e) {
      debugPrint('Firestore fetchNearbyDoctors error: $e');
      throw Exception('Failed to load nearby doctors');
    }
  }

  // =========================================================================
  // GEOCODING (Direct Nominatim client with BD filter)
  // =========================================================================

  /// Direct OpenStreetMap Nominatim geocoding with 1-req/sec safety header
  static Future<List<Map<String, dynamic>>> fetchGeocodeSuggestions(String query) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=2&countrycodes=bd',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'DoctorDesk-Flutter/1.0 (student project, contact: dev@doctordesk.bd)',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((item) {
          return {
            'displayName': item['display_name'] ?? '',
            'lat': double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0,
            'lng': double.tryParse(item['lon']?.toString() ?? '0') ?? 0.0,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Direct Nominatim geocode error: $e');
    }
    return [];
  }

  // =========================================================================
  // JOURNAL & MOOD
  // =========================================================================

  static Future<Map<String, dynamic>?> fetchTodayFeeling() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;

      final startOfDay = DateTime.now();
      final startTimestamp = DateTime(startOfDay.year, startOfDay.month, startOfDay.day);

      final snapshot = await _db
          .collection('journal')
          .where('userId', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startTimestamp))
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
    } catch (e) {
      debugPrint('Firestore fetchTodayFeeling error: $e');
    }
    return null;
  }

  static Future<bool> logFeeling({
    required String feeling,
    String? note,
    String? gratitudeText,
  }) async {
    try {
      final uid = _auth.currentUser?.uid ?? 'guest';
      await _db.collection('journal').add({
        'userId': uid,
        'feeling': feeling.toLowerCase(),
        'note': note ?? '',
        'gratitudeText': gratitudeText ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Firestore logFeeling error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchJournalEntries() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return [];

      final snapshot = await _db
          .collection('journal')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();

      return snapshot.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        final ts = data['createdAt'];
        if (ts is Timestamp) {
          data['createdAt'] = ts.toDate().toIso8601String();
        }
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Firestore fetchJournalEntries error: $e');
      return [];
    }
  }

  // =========================================================================
  // REVIEWS & BMDC CLAIMS
  // =========================================================================

  static Future<List<Map<String, dynamic>>> fetchReviews(String doctorId) async {
    return RtdbService.fetchDoctorRatings(doctorId);
  }

  static Future<Map<String, dynamic>> submitReview(
    String doctorId, {
    required String patientUid,
    required int rating,
    String comment = '',
    String? proofImageUrl,
  }) async {
    // 1. Write to Firebase Realtime Database
    final rtdbResult = await RtdbService.submitRating(
      doctorId: doctorId,
      userId: patientUid,
      rating: rating,
      comment: comment,
      proofImageUrl: proofImageUrl,
    );

    // 2. Dual-write to Firestore for offline caching & security rules parity
    try {
      final reviewDocId = '${doctorId}_$patientUid';
      await _db.collection('reviews').doc(reviewDocId).set({
        'doctorId': doctorId,
        'userId': patientUid,
        'patientUid': patientUid,
        'rating': rating,
        'comment': comment,
        'proofImageUrl': proofImageUrl,
        'isProofVerified': proofImageUrl != null && proofImageUrl.isNotEmpty,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Firestore review dual-write notice: $e');
    }

    return rtdbResult;
  }

  static Future<bool> checkCanReview(String doctorId, String patientUid, {Map<String, dynamic>? doctorData}) async {
    try {
      final eligibility = await RtdbService.checkRatingEligibility(
        doctorId: doctorId,
        userId: patientUid,
        doctorData: doctorData,
      );
      return eligibility.canRate;
    } catch (_) {
      return true;
    }
  }

  static Future<Map<String, dynamic>> claimDoctor(
    String doctorId, {
    required String bmdcRegNumber,
    required String claimedByUid,
    String? certificateImageUrl,
  }) async {
    final doctorRef = _db.collection('doctors').doc(doctorId);
    await doctorRef.update({
      'bmdcRegNumber': bmdcRegNumber,
      'claimedByUid': claimedByUid,
      'certificateImageUrl': certificateImageUrl,
      'isClaimed': true,
      // isBmdcVerified stays false until manual admin review
    });

    return {
      'isClaimed': true,
      'isBmdcVerified': false,
    };
  }

  // =========================================================================
  // USER PROFILES & ROLES SYNC
  // =========================================================================

  static Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    try {
      final docSnap = await _db.collection('users').doc(uid).get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        data['uid'] = docSnap.id;

        // Check if user is an admin
        final adminDoc = await _db.collection('admins').doc(uid).get();
        if (adminDoc.exists) {
          final roles = (data['roles'] as Map<String, dynamic>?) ?? {};
          roles['isAdmin'] = true;
          data['roles'] = roles;
        }

        return data;
      }
    } catch (e) {
      debugPrint('Firestore fetchUserProfile error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> syncUser({
    required String uid,
    String? email,
    String? name,
    String? phone,
    String? role,
    bool isDoctor = false,
  }) async {
    try {
      final userRef = _db.collection('users').doc(uid);
      final existing = await userRef.get();
      final wantsDoctor = isDoctor || role == 'doctor';

      if (!existing.exists) {
        final isDemo = (email == 'demo@mail.com');
        final userData = <String, dynamic>{
          'uid': uid,
          'email': email ?? '',
          'name': name ?? '',
          'phone': phone ?? '',
          'isDemoAccount': isDemo,
          'roles': {
            'isDoctor': isDemo, // Doctor role is allocated via database only; demo has pre-set access
            'isOperator': isDemo,
            'isAdmin': isDemo,
          },
          'chamberCount': isDemo ? 1 : 0,
          'doctorProfileId': isDemo ? 'doctor_1' : null,
          'operatorAssignments': isDemo ? ['chamber-1'] : [],
          'createdAt': FieldValue.serverTimestamp(),
        };

        if (wantsDoctor && !isDemo) {
          userData['doctorApplication'] = {
            'status': 'pending',
            'appliedAt': FieldValue.serverTimestamp(),
            'phone': phone ?? '',
            'name': name ?? '',
            'email': email ?? '',
          };
        }

        await userRef.set(userData);

        if (isDemo) {
          await _db.collection('admins').doc(uid).set({'isAdmin': true});
        }

        return userData;
      } else {
        final updates = <String, dynamic>{};
        if (name != null && name.isNotEmpty && (existing.data()?['name'] == null || existing.data()?['name'] == '')) {
          updates['name'] = name;
        }
        if (email != null && email.isNotEmpty && (existing.data()?['email'] == null || existing.data()?['email'] == '')) {
          updates['email'] = email;
        }
        if (phone != null && phone.isNotEmpty && (existing.data()?['phone'] == null || existing.data()?['phone'] == '')) {
          updates['phone'] = phone;
        }
        if (wantsDoctor) {
          final isAlreadyDoctor = existing.data()?['roles']?['isDoctor'] == true;
          if (!isAlreadyDoctor) {
            updates['doctorApplication'] = {
              'status': 'pending',
              'appliedAt': FieldValue.serverTimestamp(),
              'phone': phone ?? existing.data()?['phone'] ?? '',
              'name': name ?? existing.data()?['name'] ?? '',
              'email': email ?? existing.data()?['email'] ?? '',
            };
          }
        }
        if (updates.isNotEmpty) {
          await userRef.update(updates);
        }
        final merged = Map<String, dynamic>.from(existing.data() ?? {});
        merged.addAll(updates);
        return merged;
      }
    } catch (e) {
      debugPrint('Firestore syncUser error: $e');
      return null;
    }
  }

  /// Fetches pending doctor applications for admin review from the database
  static Future<List<Map<String, dynamic>>> fetchDoctorApplications() async {
    try {
      final snap = await _db
          .collection('users')
          .where('doctorApplication.status', isEqualTo: 'pending')
          .get();
      return snap.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint('Firestore fetchDoctorApplications error: $e');
      return [];
    }
  }

  /// Allocates or revokes the Doctor role in the database for a user (Admin only).
  /// If NID and BMDC are provided, verified badge/status can be allocated.
  static Future<void> setDoctorRole({
    required String uid,
    required bool isDoctor,
    bool isBmdcVerified = false,
    String? doctorProfileId,
    String? nid,
    String? bmdcNumber,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final updates = <String, dynamic>{
      'roles.isDoctor': isDoctor,
      'chamberCount': isDoctor ? 1 : 0,
      'doctorApplication.status': isDoctor ? 'approved' : 'revoked',
      'doctorApplication.reviewedAt': FieldValue.serverTimestamp(),
      'doctorApplication.reviewedByUid': _auth.currentUser?.uid,
      'isBmdcVerified': isBmdcVerified,
    };
    if (nid != null && nid.isNotEmpty) updates['nid'] = nid;
    if (bmdcNumber != null && bmdcNumber.isNotEmpty) updates['bmdcRegNumber'] = bmdcNumber;
    if (doctorProfileId != null) {
      updates['doctorProfileId'] = doctorProfileId;
    }
    await userRef.update(updates);
  }

  /// Submits an application for the doctor role to the database with optional NID and BMDC
  static Future<void> applyForDoctorRole({
    required String uid,
    required String phone,
    String? name,
    String? nid,
    String? bmdcNumber,
    String? speciality,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final hasDocs = (nid != null && nid.isNotEmpty) || (bmdcNumber != null && bmdcNumber.isNotEmpty);
    await userRef.set({
      'phone': phone,
      'doctorApplication': {
        'status': 'pending',
        'appliedAt': FieldValue.serverTimestamp(),
        'phone': phone,
        'name': name ?? '',
        'nid': nid ?? '',
        'bmdcNumber': bmdcNumber ?? '',
        'speciality': speciality ?? '',
        'hasProvidedVerificationDocs': hasDocs,
      },
    }, SetOptions(merge: true));
  }

  /// Sets or revokes moderator role. Only Admins can execute this.
  static Future<void> setModeratorRole({
    required String uid,
    required bool isModerator,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    await userRef.update({
      'roles.isModerator': isModerator,
      'moderatorUpdatedBy': _auth.currentUser?.uid,
      'moderatorUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Fetches users with moderator role
  static Future<List<Map<String, dynamic>>> fetchModerators() async {
    try {
      final snap = await _db
          .collection('users')
          .where('roles.isModerator', isEqualTo: true)
          .get();
      return snap.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint('Firestore fetchModerators error: $e');
      return [];
    }
  }

  // =========================================================================
  // REAL-TIME FEED & VIDEO POSTS
  // =========================================================================

  /// Stream of feed posts ordered by newest first
  static Stream<QuerySnapshot<Map<String, dynamic>>> feedPostsStream({String? typeFilter}) {
    Query<Map<String, dynamic>> query = _db.collection('posts').orderBy('timestamp', descending: true);
    if (typeFilter != null && typeFilter != 'All') {
      query = query.where('type', isEqualTo: typeFilter);
    }
    return query.snapshots();
  }

  /// Creates a post in the feed.
  /// Doctors, Admins, and Moderators can post videos and tips.
  /// Patients and Operators can ask questions.
  static Future<String> createFeedPost({
    required String type, // 'video' | 'tip' | 'question'
    required String title,
    String? content,
    String? youtubeUrl,
    String? authorName,
    String? authorRole,
    bool isBmdcVerified = false,
  }) async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? 'anonymous_user';
    final name = authorName ?? user?.displayName ?? 'Community Member';
    final role = authorRole ?? 'patient';

    final docRef = await _db.collection('posts').add({
      'type': type,
      'title': title,
      'content': content ?? '',
      'youtubeUrl': youtubeUrl ?? '',
      'userId': uid,
      'authorName': name,
      'authorRole': role,
      'isBmdcVerified': isBmdcVerified,
      'timestamp': FieldValue.serverTimestamp(),
      'answer': null,
      'likesCount': 0,
      'commentsCount': 0,
    });

    return docRef.id;
  }

  /// Answers a community question or FAQ.
  /// Allowed for Doctors, Admins, and Moderators.
  static Future<void> answerQuestion({
    required String postId,
    required String answerContent,
    String? doctorName,
    String? doctorRole,
  }) async {
    final name = doctorName ?? _auth.currentUser?.displayName ?? 'Dr. Specialist';
    final role = doctorRole ?? 'doctor';

    await _db.collection('posts').doc(postId).update({
      'answer': {
        'content': answerContent,
        'authorName': name,
        'authorRole': role,
        'authorUid': _auth.currentUser?.uid,
        'answeredAt': DateTime.now().toIso8601String(),
      },
    });
  }

  /// Adds a comment to a feed post.
  /// Allowed for all roles (patients, operators, doctors, admins).
  static Future<void> addPostComment({
    required String postId,
    required String comment,
    String? authorName,
    String? authorRole,
  }) async {
    final uid = _auth.currentUser?.uid ?? 'guest';
    final name = authorName ?? _auth.currentUser?.displayName ?? 'Community Member';
    final role = authorRole ?? 'patient';

    final postRef = _db.collection('posts').doc(postId);
    await postRef.collection('comments').add({
      'postId': postId,
      'userId': uid,
      'authorName': name,
      'authorRole': role,
      'comment': comment,
      'timestamp': FieldValue.serverTimestamp(),
    });

    try {
      await postRef.update({
        'commentsCount': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  /// Stream of comments for a specific post
  static Stream<QuerySnapshot<Map<String, dynamic>>> postCommentsStream(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  /// Deletes a post (Author, Moderator, or Admin)
  static Future<void> deleteFeedPost(String postId) async {
    await _db.collection('posts').doc(postId).delete();
  }

  // =========================================================================
  // SPECIALTY FEEDBACK (Analytics / accuracy loop)
  // =========================================================================

  static Future<void> submitSpecialtyFeedback({
    required String inputText,
    required String matchedSpecialty,
    required String source,
    required bool liked,
    String language = 'unknown',
  }) async {
    try {
      await _db.collection('specialty_feedback').add({
        'inputText': inputText,
        'matchedSpecialty': matchedSpecialty,
        'source': source,
        'liked': liked,
        'language': language,
        'userUid': _auth.currentUser?.uid,
      });
    } catch (_) {}
  }

  // =========================================================================
  // APPOINTMENTS & QUEUE MANAGEMENT
  // =========================================================================

  static Future<List<Map<String, dynamic>>> fetchTodayQueue(String chamberId) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection('appointments');
      if (chamberId != 'demo-chamber') {
        query = query.where('chamberId', isEqualTo: chamberId);
      }
      query = query.orderBy('queuePosition', descending: false);

      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['_id'] = doc.id;
        data['id'] = doc.id;
        final st = data['scheduledTime'];
        if (st is Timestamp) {
          data['scheduledTime'] = st.toDate().toIso8601String();
        }
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Firestore fetchTodayQueue error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> createAppointment({
    required String patientName,
    required DateTime scheduledTime,
    String? chamberId,
    String? doctorId,
    String? operatorNote,
    String status = 'waiting',
  }) async {
    final countSnap = await _db.collection('appointments').count().get();
    final count = countSnap.count ?? 0;

    final data = <String, dynamic>{
      'patientName': patientName,
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'chamberId': chamberId ?? 'demo-chamber',
      'doctorId': doctorId ?? 'doctor_1',
      'operatorNote': operatorNote ?? '',
      'status': status,
      'queuePosition': count + 1,
      'userId': _auth.currentUser?.uid ?? 'guest',
      'createdAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _db.collection('appointments').add(data);
    return {
      '_id': docRef.id,
      'id': docRef.id,
      ...data,
      'scheduledTime': scheduledTime.toIso8601String(),
    };
  }

  static Future<void> updateAppointment(String id, Map<String, dynamic> updates) async {
    final cleanUpdates = Map<String, dynamic>.from(updates);
    if (cleanUpdates.containsKey('scheduledTime') && cleanUpdates['scheduledTime'] is String) {
      final dt = DateTime.tryParse(cleanUpdates['scheduledTime']);
      if (dt != null) {
        cleanUpdates['scheduledTime'] = Timestamp.fromDate(dt);
      }
    }
    await _db.collection('appointments').doc(id).update(cleanUpdates);
  }

  static Future<void> updateQueueOrder(List<Map<String, dynamic>> updates) async {
    final batch = _db.batch();
    for (final u in updates) {
      final id = (u['id'] ?? u['_id']) as String?;
      final pos = u['queuePosition'] as int?;
      if (id != null && pos != null) {
        final ref = _db.collection('appointments').doc(id);
        batch.update(ref, {'queuePosition': pos});
      }
    }
    await batch.commit();
  }

  static Future<void> deleteAppointment(String id) async {
    await _db.collection('appointments').doc(id).delete();
  }

  static Future<void> clearAllAppointments() async {
    final snapshot = await _db.collection('appointments').get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}

