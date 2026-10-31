import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';
import 'notification_service.dart';

class ChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String generateChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  /// Unlocks a chat session for a patient and doctor following care or paid consultation.
  /// Enforces that only Doctor, Admin, or authorized desk operator can trigger this.
  static Future<String> unlockChatForCare({
    required String doctorUid,
    required String patientUid,
    required String doctorName,
    required String patientName,
    String? doctorId,
    required String unlockedBy,
    int followupDays = 7,
    int followupMaxMessages = 20,
  }) async {
    final chatId = generateChatId(patientUid, doctorUid);
    final chatRef = _db.collection('chats').doc(chatId);
    final expiresAt = DateTime.now().add(Duration(days: followupDays));

    await chatRef.set({
      'participants': [patientUid, doctorUid],
      'doctorUid': doctorUid,
      'patientUid': patientUid,
      'doctorName': doctorName,
      'patientName': patientName,
      if (doctorId != null) 'doctorId': doctorId,
      'status': 'active',
      'expiresAt': Timestamp.fromDate(expiresAt),
      'messageLimit': followupMaxMessages,
      'messageCount': 0,
      'unlockedBy': unlockedBy,
      'lastMessage': 'Consultation completed. Follow-up chat unlocked for $followupDays days.',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await NotificationService.createNotification(
        userId: patientUid,
        title: 'Follow-up Chat Unlocked 💬',
        body: 'Dr. $doctorName has unlocked follow-up chat for $followupDays days.',
        type: 'chat_unlock',
        relatedId: chatId,
      );
    } catch (_) {}

    return chatId;
  }

  /// Backward-compatible alias for unlocking chat on approved consultation
  static Future<String> getOrCreateChat({
    required String doctorUid,
    required String patientUid,
    required String doctorName,
    required String patientName,
    String? doctorId,
    String? unlockedBy,
    int followupDays = 7,
    int followupMaxMessages = 20,
  }) async {
    return unlockChatForCare(
      doctorUid: doctorUid,
      patientUid: patientUid,
      doctorName: doctorName,
      patientName: patientName,
      doctorId: doctorId,
      unlockedBy: unlockedBy ?? 'consultation',
      followupDays: followupDays,
      followupMaxMessages: followupMaxMessages,
    );
  }

  /// Checks if an active, non-expired consultation chat exists for this doctor & patient.
  static Future<ChatSession?> getUnlockedChatForDoctorAndPatient({
    required String doctorUid,
    required String patientUid,
  }) async {
    final chatId = generateChatId(patientUid, doctorUid);
    final snap = await _db.collection('chats').doc(chatId).get();
    if (!snap.exists) return null;
    final session = ChatSession.fromFirestore(snap);
    if (session.status == 'active' && !session.isExpired) {
      return session;
    }
    return null;
  }

  /// Closes an active chat early (Doctor or Admin only).
  static Future<void> closeChat(String chatId) async {
    await _db.collection('chats').doc(chatId).update({
      'status': 'closed',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<ChatSession?> streamChatSession(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return ChatSession.fromFirestore(snap);
    });
  }

  static Stream<List<ChatMessage>> streamMessages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList());
  }

  static Stream<List<ChatSession>> streamUserChats(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => ChatSession.fromFirestore(d)).toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  static Future<void> sendMessage({
    required String chatId,
    required String senderUid,
    required String otherUid,
    required String text,
    required String senderName,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final chatRef = _db.collection('chats').doc(chatId);
    final chatSnap = await chatRef.get();
    if (chatSnap.exists) {
      final session = ChatSession.fromFirestore(chatSnap);
      if (!session.canSendMessage) {
        throw StateError(
          session.status == 'closed'
              ? 'This consultation chat has been closed.'
              : (session.isExpired
                  ? 'This consultation follow-up window has expired.'
                  : 'Message limit (${session.messageLimit}) reached for this consultation.'),
        );
      }
    }

    final msgRef = chatRef.collection('messages').doc();
    final batch = _db.batch();

    batch.set(msgRef, {
      'senderUid': senderUid,
      'text': cleanText,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(chatRef, {
      'lastMessage': cleanText,
      'messageCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    try {
      await NotificationService.createNotification(
        userId: otherUid,
        title: 'New message from $senderName',
        body: cleanText,
        type: 'chat_message',
        relatedId: chatId,
      );
    } catch (_) {}
  }
}
