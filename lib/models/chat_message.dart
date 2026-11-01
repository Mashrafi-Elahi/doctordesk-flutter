import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String senderUid;
  final String text;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['createdAt'];
    return ChatMessage(
      id: doc.id,
      senderUid: (data['senderUid'] ?? '').toString(),
      text: (data['text'] ?? '').toString(),
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'senderUid': senderUid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class ChatSession {
  final String id;
  final List<String> participants;
  final String patientUid;
  final String doctorUid;
  final String lastMessage;
  final DateTime updatedAt;
  final String doctorName;
  final String patientName;
  final String? doctorId;
  final String status; // 'active' | 'expired' | 'closed'
  final DateTime? expiresAt;
  final int messageLimit;
  final int messageCount;
  final String? unlockedBy;

  ChatSession({
    required this.id,
    required this.participants,
    required this.patientUid,
    required this.doctorUid,
    required this.lastMessage,
    required this.updatedAt,
    required this.doctorName,
    required this.patientName,
    this.doctorId,
    this.status = 'active',
    this.expiresAt,
    this.messageLimit = 20,
    this.messageCount = 0,
    this.unlockedBy,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isLimitReached => messageCount >= messageLimit;
  bool get canSendMessage => status == 'active' && !isExpired && !isLimitReached;

  factory ChatSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['updatedAt'];
    final expTs = data['expiresAt'];
    final pUid = (data['patientUid'] ?? '').toString();
    final dUid = (data['doctorUid'] ?? '').toString();
    final rawParts = data['participants'];
    final parts = rawParts is List
        ? rawParts.map((e) => e.toString()).toList()
        : [pUid, dUid];

    return ChatSession(
      id: doc.id,
      participants: parts,
      patientUid: pUid,
      doctorUid: dUid,
      lastMessage: (data['lastMessage'] ?? '').toString(),
      updatedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      doctorName: (data['doctorName'] ?? 'Doctor').toString(),
      patientName: (data['patientName'] ?? 'Patient').toString(),
      doctorId: data['doctorId'] as String?,
      status: (data['status'] ?? 'active').toString(),
      expiresAt: expTs is Timestamp ? expTs.toDate() : null,
      messageLimit: (data['messageLimit'] as num?)?.toInt() ?? 20,
      messageCount: (data['messageCount'] as num?)?.toInt() ?? 0,
      unlockedBy: data['unlockedBy'] as String?,
    );
  }
}
