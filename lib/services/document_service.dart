// document_service.dart
//
// Manages patient health documents locally (SharedPreferences JSON store)
// and allows optional upload to Firebase Storage when sharing with a doctor.
// No Firestore reads are needed — only Storage PUT on explicit user action.

import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata for one uploaded document stored locally.
class HealthDocument {
  final String localId;        // UUID-like: uid_timestamp
  final String fileName;
  final String localPath;      // Absolute path on device
  final DateTime savedAt;
  final String type;           // 'prescription', 'lab_report', 'xray', 'other'
  String? sharedUrl;           // Set when uploaded to Firebase Storage
  DateTime? sharedAt;

  HealthDocument({
    required this.localId,
    required this.fileName,
    required this.localPath,
    required this.savedAt,
    required this.type,
    this.sharedUrl,
    this.sharedAt,
  });

  factory HealthDocument.fromJson(Map<String, dynamic> json) => HealthDocument(
    localId: json['localId'] as String,
    fileName: json['fileName'] as String,
    localPath: json['localPath'] as String,
    savedAt: DateTime.parse(json['savedAt'] as String),
    type: (json['type'] as String?) ?? 'other',
    sharedUrl: json['sharedUrl'] as String?,
    sharedAt: json['sharedAt'] != null
        ? DateTime.tryParse(json['sharedAt'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'fileName': fileName,
    'localPath': localPath,
    'savedAt': savedAt.toIso8601String(),
    'type': type,
    'sharedUrl': sharedUrl,
    'sharedAt': sharedAt?.toIso8601String(),
  };
}

class DocumentService {
  static const String _prefsKey = 'health_documents_v1';
  static final ImagePicker _picker = ImagePicker();

  // ── Local Storage ────────────────────────────────────────────────────────

  /// Loads all locally stored documents for this device.
  static Future<List<HealthDocument>> loadLocalDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> list = jsonDecode(raw);
      return list
          .map((e) => HealthDocument.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } catch (e) {
      debugPrint('DocumentService.loadLocalDocuments error: $e');
      return [];
    }
  }

  /// Saves the full documents list back to SharedPreferences.
  static Future<void> _saveList(List<HealthDocument> docs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(docs.map((d) => d.toJson()).toList()),
    );
  }

  /// Picks an image from gallery or camera and stores metadata locally.
  static Future<HealthDocument?> pickAndSaveDocument({
    required String type,
    bool fromCamera = false,
  }) async {
    try {
      final XFile? file = fromCamera
          ? await _picker.pickImage(source: ImageSource.camera, imageQuality: 85)
          : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);

      if (file == null) return null;

      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final localId = '${uid}_$ts';
      final fileName = file.name.isEmpty ? 'doc_$ts.jpg' : file.name;

      final doc = HealthDocument(
        localId: localId,
        fileName: fileName,
        localPath: file.path,
        savedAt: DateTime.now(),
        type: type,
      );

      final docs = await loadLocalDocuments();
      docs.insert(0, doc);
      await _saveList(docs);
      return doc;
    } catch (e) {
      debugPrint('DocumentService.pickAndSaveDocument error: $e');
      return null;
    }
  }

  /// Removes a document from local storage (does not delete from Firebase).
  static Future<void> deleteLocalDocument(String localId) async {
    final docs = await loadLocalDocuments();
    docs.removeWhere((d) => d.localId == localId);
    await _saveList(docs);
  }

  // ── Firebase Storage Upload (on-demand share) ─────────────────────────────

  /// Uploads document to Firebase Storage under `patient_docs/{uid}/{localId}/`.
  /// Returns the public download URL.
  /// Only called when user explicitly taps "Share with Doctor".
  static Future<String> uploadToFirebase(
    HealthDocument doc, {
    void Function(double progress)? onProgress,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Must be signed in to share documents.');

    final file = File(doc.localPath);
    if (!file.existsSync()) {
      throw StateError('Document file not found on device.');
    }

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('patient_docs')
        .child(uid)
        .child(doc.localId)
        .child(doc.fileName);

    final uploadTask = storageRef.putFile(
      file,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedBy': uid,
          'documentType': doc.type,
          'originalName': doc.fileName,
        },
      ),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }

    final snapshot = await uploadTask;
    final url = await snapshot.ref.getDownloadURL();

    // Persist the shared URL locally so the user sees it in the document list
    final docs = await loadLocalDocuments();
    final idx = docs.indexWhere((d) => d.localId == doc.localId);
    if (idx >= 0) {
      docs[idx].sharedUrl = url;
      docs[idx].sharedAt = DateTime.now();
      await _saveList(docs);
    }

    return url;
  }

  /// Returns a shareable link for a document that has already been uploaded.
  /// For production, generate a signed URL with expiry here.
  static Future<String> getShareableLink(HealthDocument doc) async {
    if (doc.sharedUrl == null) {
      throw StateError('Document has not been uploaded yet. Upload first.');
    }
    // Firebase Storage download URLs are already accessible for the file path.
    return doc.sharedUrl!;
  }
}
