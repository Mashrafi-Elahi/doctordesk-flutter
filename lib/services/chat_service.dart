import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';
import 'notification_service.dart';

class ChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String generateChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  static Future<String> getOrCreateChat({
    required String doctorUid,
    required String patientUid,
    required String doctorName,
    required String patientName,
    String? doctorId,
  }) async {
    final chatId = generateChatId(patientUid, doctorUid);
    final chatRef = _db.collection('chats').doc(chatId);

    final snap = await chatRef.get();
    if (!snap.exists) {
      await chatRef.set({
        'participants': [patientUid, doctorUid],
        'doctorUid': doctorUid,
        'patientUid': patientUid,
        'doctorName': doctorName,
        'patientName': patientName,
        if (doctorId != null) 'doctorId': doctorId,
        'lastMessage': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    return chatId;
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
    final msgRef = chatRef.collection('messages').doc();

    await msgRef.set({
      'senderUid': senderUid,
      'text': cleanText,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await chatRef.update({
      'lastMessage': cleanText,
      'updatedAt': FieldValue.serverTimestamp(),
    });

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
