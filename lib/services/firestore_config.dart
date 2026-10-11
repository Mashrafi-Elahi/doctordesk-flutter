/// Global configuration flag controlling whether DoctorDesk connects
/// to the Node.js/MongoDB ApiService or the direct Cloud Firestore backend.
class FirestoreConfig {
  /// Build-time flag: --dart-define=USE_FIRESTORE=true (default: true)
  static const bool useFirestore = bool.fromEnvironment('USE_FIRESTORE', defaultValue: true);
}
