/// Global configuration flag for the direct Cloud Firestore backend.
/// The legacy HTTP service is retained only for backwards-compatible builds;
/// DoctorDesk's active production data store is Firebase/Firestore.
class FirestoreConfig {
  /// Build-time flag: --dart-define=USE_FIRESTORE=true (default: true)
  static const bool useFirestore =
      bool.fromEnvironment('USE_FIRESTORE', defaultValue: true);
}
