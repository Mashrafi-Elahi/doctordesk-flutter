import 'package:cloud_firestore/cloud_firestore.dart';

/// Single source of truth for all appointment-related Firestore queries.
/// Used by: operator desk, doctor queue desk, doctor home counters,
/// manage-tab badges, and patient appointments screen.
class AppointmentQueries {
  static final _db = FirebaseFirestore.instance;

  /// Pending requests for an operator: chamberId in assigned chambers + status == 'requested'.
  /// No scheduledTime filter — requested appointments may have null or future time.
  static Query<Map<String, dynamic>> pendingRequestsForOperator(
      List<String> chamberIds) {
    if (chamberIds.isEmpty) {
      return _db
          .collection('appointments')
          .where('status', isEqualTo: 'requested')
          .where('chamberId', isEqualTo: '__no_match__');
    }
    return _db
        .collection('appointments')
        .where('chamberId', whereIn: chamberIds)
        .where('status', isEqualTo: 'requested')
        .orderBy('createdAt', descending: false);
  }

  /// Pending requests for a doctor: doctorId matches + status == 'requested'.
  /// No scheduledTime filter.
  static Query<Map<String, dynamic>> pendingRequestsForDoctor(
      String doctorProfileId) {
    return _db
        .collection('appointments')
        .where('doctorId', isEqualTo: doctorProfileId)
        .where('status', isEqualTo: 'requested')
        .orderBy('createdAt', descending: false);
  }

  /// Today's active queue for an operator chamber:
  /// status in [confirmed, in_progress] + scheduledTime within today.
  static Query<Map<String, dynamic>> todayQueueForChamber(String chamberId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _db
        .collection('appointments')
        .where('chamberId', isEqualTo: chamberId)
        .where('status', whereIn: ['confirmed', 'in_progress'])
        .where('scheduledTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledTime', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('scheduledTime');
  }

  /// Today's active queue for a doctor across all chambers.
  static Query<Map<String, dynamic>> todayQueueForDoctor(
      String doctorProfileId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _db
        .collection('appointments')
        .where('doctorId', isEqualTo: doctorProfileId)
        .where('status', whereIn: ['confirmed', 'in_progress'])
        .where('scheduledTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledTime', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('scheduledTime');
  }

  /// All appointments for a patient, newest first.
  static Query<Map<String, dynamic>> patientAppointments(String userId) {
    return _db
        .collection('appointments')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true);
  }

  /// Count of pending requests for operator (for badge).
  static Stream<int> pendingRequestCountForOperator(List<String> chamberIds) {
    if (chamberIds.isEmpty) return Stream.value(0);
    return pendingRequestsForOperator(chamberIds)
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Count of pending requests for doctor (for badge).
  static Stream<int> pendingRequestCountForDoctor(String doctorProfileId) {
    if (doctorProfileId.isEmpty) return Stream.value(0);
    return pendingRequestsForDoctor(doctorProfileId)
        .snapshots()
        .map((s) => s.docs.length);
  }
}
