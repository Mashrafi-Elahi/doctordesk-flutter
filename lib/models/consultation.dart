import 'package:cloud_firestore/cloud_firestore.dart';

class Consultation {
  final String id;
  final String patientUid;
  final String patientName;
  final String doctorId;
  final String doctorUid;
  final String doctorName;
  final double amount;
  final String paymentMethod; // 'bkash' | 'nagad'
  final String trxId;
  final String status; // 'pending_payment' | 'paid_unconfirmed' | 'active' | 'completed' | 'refunded'
  final String? chatId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? rejectionReason;

  Consultation({
    required this.id,
    required this.patientUid,
    required this.patientName,
    required this.doctorId,
    required this.doctorUid,
    required this.doctorName,
    required this.amount,
    required this.paymentMethod,
    required this.trxId,
    required this.status,
    this.chatId,
    required this.createdAt,
    this.updatedAt,
    this.rejectionReason,
  });

  factory Consultation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final cr = data['createdAt'];
    final up = data['updatedAt'];

    return Consultation(
      id: doc.id,
      patientUid: (data['patientUid'] ?? '').toString(),
      patientName: (data['patientName'] ?? 'Patient').toString(),
      doctorId: (data['doctorId'] ?? '').toString(),
      doctorUid: (data['doctorUid'] ?? '').toString(),
      doctorName: (data['doctorName'] ?? 'Doctor').toString(),
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (data['paymentMethod'] ?? 'bkash').toString(),
      trxId: (data['trxId'] ?? '').toString(),
      status: (data['status'] ?? 'pending_payment').toString(),
      chatId: data['chatId'] as String?,
      createdAt: cr is Timestamp ? cr.toDate() : DateTime.now(),
      updatedAt: up is Timestamp ? up.toDate() : null,
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'patientUid': patientUid,
        'patientName': patientName,
        'doctorId': doctorId,
        'doctorUid': doctorUid,
        'doctorName': doctorName,
        'amount': amount,
        'paymentMethod': paymentMethod,
        'trxId': trxId,
        'status': status,
        if (chatId != null) 'chatId': chatId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      };
}
