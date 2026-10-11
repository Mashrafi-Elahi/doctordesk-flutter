import '../models/doctor.dart';
import 'api_service.dart';
import 'firestore_config.dart';
import 'firestore_service.dart';

/// Unified data service for DoctorDesk.
/// Automatically selects between Cloud Firestore and Node.js/Express backend
/// using the compile-time flag `USE_FIRESTORE`.
class DataService {
  static bool get isFirestore => FirestoreConfig.useFirestore;

  // --- DOCTOR DIRECTORY & DISCOVERY ---

  static Future<Map<String, dynamic>> fetchDoctors({
    int page = 1,
    int limit = 20,
    String? search,
    String? speciality,
  }) {
    if (isFirestore) {
      return FirestoreService.fetchDoctors(
        page: page,
        limit: limit,
        search: search,
        speciality: speciality,
      );
    }
    return ApiService.fetchDoctors(
      page: page,
      limit: limit,
      search: search,
      speciality: speciality,
    );
  }

  static Future<Doctor> fetchDoctorById(String id) {
    if (isFirestore) {
      return FirestoreService.fetchDoctorById(id);
    }
    return ApiService.fetchDoctorById(id);
  }

  static Future<List<Map<String, dynamic>>> fetchSpecialities() {
    if (isFirestore) {
      return FirestoreService.fetchSpecialities();
    }
    return ApiService.fetchSpecialities();
  }

  static Future<List<Doctor>> fetchNearbyDoctors({
    required double lat,
    required double lng,
    int radiusKm = 10,
    String? speciality,
    int page = 1,
    int limit = 20,
  }) {
    if (isFirestore) {
      return FirestoreService.fetchNearbyDoctors(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        speciality: speciality,
        page: page,
        limit: limit,
      );
    }
    return ApiService.fetchNearbyDoctors(
      lat: lat,
      lng: lng,
      radiusKm: radiusKm,
      speciality: speciality,
      page: page,
      limit: limit,
    );
  }

  static Future<List<Map<String, dynamic>>> fetchGeocodeSuggestions(String query) {
    if (isFirestore) {
      return FirestoreService.fetchGeocodeSuggestions(query);
    }
    return ApiService.fetchGeocodeSuggestions(query);
  }

  // --- JOURNAL & FEELINGS ---

  static Future<Map<String, dynamic>?> fetchTodayFeeling() {
    if (isFirestore) {
      return FirestoreService.fetchTodayFeeling();
    }
    return ApiService.fetchTodayFeeling();
  }

  static Future<bool> logFeeling({
    required String feeling,
    String? note,
    String? gratitudeText,
  }) {
    if (isFirestore) {
      return FirestoreService.logFeeling(
        feeling: feeling,
        note: note,
        gratitudeText: gratitudeText,
      );
    }
    return ApiService.logFeeling(
      feeling: feeling,
      note: note,
      gratitudeText: gratitudeText,
    );
  }

  static Future<List<Map<String, dynamic>>> fetchJournalEntries() {
    if (isFirestore) {
      return FirestoreService.fetchJournalEntries();
    }
    return ApiService.fetchJournalEntries();
  }

  // --- REVIEWS & BMDC CLAIMS ---

  static Future<List<Map<String, dynamic>>> fetchReviews(String doctorId) {
    if (isFirestore) {
      return FirestoreService.fetchReviews(doctorId);
    }
    return ApiService.fetchReviews(doctorId);
  }

  static Future<Map<String, dynamic>> submitReview(
    String doctorId, {
    required String patientUid,
    required int rating,
    String comment = '',
    String? proofImageUrl,
  }) {
    if (isFirestore) {
      return FirestoreService.submitReview(
        doctorId,
        patientUid: patientUid,
        rating: rating,
        comment: comment,
        proofImageUrl: proofImageUrl,
      );
    }
    return ApiService.submitReview(
      doctorId,
      patientUid: patientUid,
      rating: rating,
      comment: comment,
      proofImageUrl: proofImageUrl,
    );
  }

  static Future<bool> checkCanReview(
    String doctorId,
    String patientUid, {
    Map<String, dynamic>? doctorData,
  }) {
    if (isFirestore) {
      return FirestoreService.checkCanReview(doctorId, patientUid, doctorData: doctorData);
    }
    return ApiService.checkCanReview(doctorId, patientUid, doctorData: doctorData);
  }

  static Future<Map<String, dynamic>> claimDoctor(
    String doctorId, {
    required String bmdcRegNumber,
    required String claimedByUid,
    String? certificateImageUrl,
  }) {
    if (isFirestore) {
      return FirestoreService.claimDoctor(
        doctorId,
        bmdcRegNumber: bmdcRegNumber,
        claimedByUid: claimedByUid,
        certificateImageUrl: certificateImageUrl,
      );
    }
    return ApiService.claimDoctor(
      doctorId,
      bmdcRegNumber: bmdcRegNumber,
      claimedByUid: claimedByUid,
      certificateImageUrl: certificateImageUrl,
    );
  }

  // --- USERS & PROFILES ---

  static Future<Map<String, dynamic>?> fetchUserProfile(String uid) {
    if (isFirestore) {
      return FirestoreService.fetchUserProfile(uid);
    }
    return ApiService.fetchUserProfile(uid);
  }

  static Future<Map<String, dynamic>?> syncUser({
    required String uid,
    String? email,
    String? name,
    String? phone,
    String? role,
    bool isDoctor = false,
  }) {
    if (isFirestore) {
      return FirestoreService.syncUser(
        uid: uid,
        email: email,
        name: name,
        phone: phone,
        role: role,
        isDoctor: isDoctor,
      );
    }
    return ApiService.syncUser(
      uid: uid,
      email: email,
      name: name,
      phone: phone,
      role: role,
      isDoctor: isDoctor,
    );
  }

  static Future<List<Map<String, dynamic>>> fetchDoctorApplications() {
    if (isFirestore) {
      return FirestoreService.fetchDoctorApplications();
    }
    return ApiService.fetchDoctorApplications();
  }

  static Future<void> setDoctorRole({
    required String uid,
    required bool isDoctor,
    String? doctorProfileId,
  }) {
    if (isFirestore) {
      return FirestoreService.setDoctorRole(
        uid: uid,
        isDoctor: isDoctor,
        doctorProfileId: doctorProfileId,
      );
    }
    return ApiService.setDoctorRole(
      uid: uid,
      isDoctor: isDoctor,
      doctorProfileId: doctorProfileId,
    );
  }

  static Future<void> applyForDoctorRole({
    required String uid,
    required String phone,
    String? name,
    String? bmdcNumber,
    String? speciality,
  }) {
    if (isFirestore) {
      return FirestoreService.applyForDoctorRole(
        uid: uid,
        phone: phone,
        name: name,
        bmdcNumber: bmdcNumber,
        speciality: speciality,
      );
    }
    return ApiService.applyForDoctorRole(
      uid: uid,
      phone: phone,
      name: name,
      bmdcNumber: bmdcNumber,
      speciality: speciality,
    );
  }

  // --- SPECIALTY ACCURACY FEEDBACK ---

  static Future<void> submitSpecialtyFeedback({
    required String inputText,
    required String matchedSpecialty,
    required String source,
    required bool liked,
    String language = 'unknown',
  }) {
    if (isFirestore) {
      return FirestoreService.submitSpecialtyFeedback(
        inputText: inputText,
        matchedSpecialty: matchedSpecialty,
        source: source,
        liked: liked,
        language: language,
      );
    }
    return ApiService.submitSpecialtyFeedback(
      inputText: inputText,
      matchedSpecialty: matchedSpecialty,
      source: source,
      liked: liked,
      language: language,
    );
  }

  // --- APPOINTMENTS & QUEUE MANAGEMENT ---

  static Future<List<Map<String, dynamic>>> fetchTodayQueue(String chamberId) {
    if (isFirestore) {
      return FirestoreService.fetchTodayQueue(chamberId);
    }
    return ApiService.fetchTodayQueue(chamberId);
  }

  static Future<Map<String, dynamic>> createAppointment({
    required String patientName,
    required DateTime scheduledTime,
    String? chamberId,
    String? doctorId,
    String? operatorNote,
    String status = 'waiting',
  }) {
    if (isFirestore) {
      return FirestoreService.createAppointment(
        patientName: patientName,
        scheduledTime: scheduledTime,
        chamberId: chamberId,
        doctorId: doctorId,
        operatorNote: operatorNote,
        status: status,
      );
    }
    return ApiService.createAppointment(
      patientName: patientName,
      scheduledTime: scheduledTime,
      chamberId: chamberId,
      doctorId: doctorId,
      operatorNote: operatorNote,
      status: status,
    );
  }

  static Future<void> updateAppointment(String id, Map<String, dynamic> updates) {
    if (isFirestore) {
      return FirestoreService.updateAppointment(id, updates);
    }
    return ApiService.updateAppointment(id, updates);
  }

  static Future<void> updateQueueOrder(List<Map<String, dynamic>> updates) {
    if (isFirestore) {
      return FirestoreService.updateQueueOrder(updates);
    }
    return ApiService.updateQueueOrder(updates);
  }

  static Future<void> deleteAppointment(String id) {
    if (isFirestore) {
      return FirestoreService.deleteAppointment(id);
    }
    return ApiService.deleteAppointment(id);
  }

  static Future<void> clearAllAppointments() {
    if (isFirestore) {
      return FirestoreService.clearAllAppointments();
    }
    return ApiService.clearAllAppointments();
  }
}
