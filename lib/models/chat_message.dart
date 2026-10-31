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
  final String lastMessage;
  final DateTime updatedAt;
  final String doctorName;
  final String patientName;
  final String? doctorId;

  ChatSession({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.updatedAt,
    required this.doctorName,
    required this.patientName,
    this.doctorId,
  });

  factory ChatSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['updatedAt'];
    final rawParts = data['participants'];
    final parts = rawParts is List
        ? rawParts.map((e) => e.toString()).toList()
        : <String>[];

    return ChatSession(
      id: doc.id,
      participants: parts,
      lastMessage: (data['lastMessage'] ?? '').toString(),
      updatedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      doctorName: (data['doctorName'] ?? 'Doctor').toString(),
      patientName: (data['patientName'] ?? 'Patient').toString(),
      doctorId: data['doctorId'] as String?,
    );
  }
}
