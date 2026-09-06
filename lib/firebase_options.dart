// File generated for DoctorDesk Firebase integration
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA9g-wpl17Z569jDSwhl2y81sWfn2UGNPE',
    appId: '1:112062167979:web:22434d5a58283fe9c270ee',
    messagingSenderId: '112062167979',
    projectId: 'docdesk-1e4cc',
    authDomain: 'docdesk-1e4cc.firebaseapp.com',
    storageBucket: 'docdesk-1e4cc.firebasestorage.app',
    measurementId: 'G-1KDM7W30C2',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA9g-wpl17Z569jDSwhl2y81sWfn2UGNPE',
    appId: '1:112062167979:android:22434d5a58283fe9c270ee',
    messagingSenderId: '112062167979',
    projectId: 'docdesk-1e4cc',
    storageBucket: 'docdesk-1e4cc.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA9g-wpl17Z569jDSwhl2y81sWfn2UGNPE',
    appId: '1:112062167979:ios:22434d5a58283fe9c270ee',
    messagingSenderId: '112062167979',
    projectId: 'docdesk-1e4cc',
    storageBucket: 'docdesk-1e4cc.firebasestorage.app',
    iosBundleId: 'com.example.doctordesk',
  );
}
