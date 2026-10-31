import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/consultation.dart';
import 'chat_service.dart';
import 'notification_service.dart';
import 'payment_provider.dart';

class ConsultationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final PaymentProvider _paymentProvider = ManualMfsPaymentProvider();

  /// Creates a consultation request with patient MFS transaction ID.
  static Future<String> createConsultationRequest({
    required String patientUid,
    required String patientName,
    required String doctorId,
    required String doctorUid,
    required String doctorName,
    required double amount,
    required String paymentMethod,
    required String trxId,
    required String senderPhone,
  }) async {
    final validation = await _paymentProvider.initiatePayment(PaymentSubmission(
      consultationId: 'temp',
      amount: amount,
      channel: paymentMethod == 'nagad' ? PaymentChannel.nagad : PaymentChannel.bkash,
      transactionId: trxId,
      senderPhone: senderPhone,
    ));

    if (!validation.success) {
      throw StateError(validation.errorMessage ?? 'Payment validation failed.');
    }

    final docRef = _db.collection('consultations').doc();
    final data = <String, dynamic>{
      'patientUid': patientUid,
      'patientName': patientName,
      'doctorId': doctorId,
      'doctorUid': doctorUid,
      'doctorName': doctorName,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'trxId': trxId.trim(),
      'senderPhone': senderPhone.trim(),
      'status': 'paid_unconfirmed',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await docRef.set(data);

    if (doctorUid.isNotEmpty) {
      try {
        await NotificationService.createNotification(
          userId: doctorUid,
          title: 'New Consultation Request 💬',
          body: '$patientName requested an online consultation (TrxID: ${trxId.trim()}). Verify to start chat.',
          type: 'consultation_requested',
          relatedId: docRef.id,
        );
      } catch (_) {}
    }

    return docRef.id;
  }

  /// Doctor or Admin approves the consultation and links the real-time chat.
  static Future<String> approveConsultation({
    required String consultationId,
    required String doctorUid,
    required String patientUid,
    required String doctorName,
    required String patientName,
    required String doctorId,
  }) async {
    final chatId = await ChatService.getOrCreateChat(
      doctorUid: doctorUid,
      patientUid: patientUid,
      doctorName: doctorName,
      patientName: patientName,
      doctorId: doctorId,
    );

    final consultRef = _db.collection('consultations').doc(consultationId);
    await consultRef.update({
      'status': 'active',
      'chatId': chatId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (patientUid.isNotEmpty) {
      try {
        await NotificationService.createNotification(
          userId: patientUid,
          title: 'Consultation Approved! 🎉',
          body: 'Your payment was verified. You can now chat directly with $doctorName.',
          type: 'consultation_approved',
          relatedId: chatId,
        );
      } catch (_) {}
    }

    return chatId;
  }

  /// Rejects the consultation request with a reason.
  static Future<void> rejectConsultation({
    required String consultationId,
    required String patientUid,
    required String doctorName,
    required String reason,
  }) async {
    final consultRef = _db.collection('consultations').doc(consultationId);
    await consultRef.update({
      'status': 'refunded',
      'rejectionReason': reason.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (patientUid.isNotEmpty) {
      try {
        await NotificationService.createNotification(
          userId: patientUid,
          title: 'Consultation Declined',
          body: 'Your consultation request with $doctorName could not be verified. Reason: ${reason.trim()}.',
          type: 'consultation_rejected',
          relatedId: consultationId,
        );
      } catch (_) {}
    }
  }

  /// Marks an active consultation as completed.
  static Future<void> completeConsultation(String consultationId) async {
    await _db.collection('consultations').doc(consultationId).update({
      'status': 'completed',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Checks if patient has an active or pending consultation with this doctor.
  static Future<Consultation?> getActiveOrPendingConsultation({
    required String patientUid,
    required String doctorId,
  }) async {
    final snap = await _db
        .collection('consultations')
        .where('patientUid', isEqualTo: patientUid)
        .where('doctorId', isEqualTo: doctorId)
        .get();

    for (final doc in snap.docs) {
      final c = Consultation.fromFirestore(doc);
      if (c.status == 'active' || c.status == 'paid_unconfirmed') {
        return c;
      }
    }
    return null;
  }

  /// Streams consultations for a patient.
  static Stream<List<Consultation>> streamPatientConsultations(String patientUid) {
    return _db
        .collection('consultations')
        .where('patientUid', isEqualTo: patientUid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => Consultation.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Streams consultations for a doctor.
  static Stream<List<Consultation>> streamDoctorConsultations(String doctorUid) {
    return _db
        .collection('consultations')
        .where('doctorUid', isEqualTo: doctorUid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => Consultation.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Streams all pending consultations for Admin or Doctor review.
  static Stream<List<Consultation>> streamPendingConsultations({String? doctorUid}) {
    Query query = _db
        .collection('consultations')
        .where('status', isEqualTo: 'paid_unconfirmed');

    if (doctorUid != null && doctorUid.isNotEmpty) {
      query = query.where('doctorUid', isEqualTo: doctorUid);
    }

    return query.snapshots().map((snap) {
      final list = snap.docs.map((d) => Consultation.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Updates doctor consultation portal settings.
  static Future<void> updateDoctorConsultSettings({
    required String doctorId,
    required bool consultEnabled,
    required double consultFee,
    required String availability,
  }) async {
    await _db.collection('doctors').doc(doctorId).set({
      'consultEnabled': consultEnabled,
      'consultFee': consultFee,
      'consultAvailability': availability.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
