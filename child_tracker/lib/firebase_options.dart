import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      case TargetPlatform.macOS:
        return macos;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCZzfmyyuqFc_xw0Yp5DffmxfvS_heONN4',
    appId: '1:616084029405:web:21029b55c2620cc6674034',
    messagingSenderId: '616084029405',
    projectId: 'child-safety-tracking',
    authDomain: 'child-safety-tracking.firebaseapp.com',
    databaseURL: 'https://child-safety-tracking-default-rtdb.firebaseio.com',
    storageBucket: 'child-safety-tracking.firebasestorage.app',
    measurementId: 'G-4F87CVSG7F',
  );

  // Temporary native fallback until the real Android/iOS Firebase app configs
  // are added with flutterfire or platform config files.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCZzfmyyuqFc_xw0Yp5DffmxfvS_heONN4',
    appId: '1:616084029405:web:21029b55c2620cc6674034',
    messagingSenderId: '616084029405',
    projectId: 'child-safety-tracking',
    databaseURL: 'https://child-safety-tracking-default-rtdb.firebaseio.com',
    storageBucket: 'child-safety-tracking.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCZzfmyyuqFc_xw0Yp5DffmxfvS_heONN4',
    appId: '1:616084029405:web:21029b55c2620cc6674034',
    messagingSenderId: '616084029405',
    projectId: 'child-safety-tracking',
    databaseURL: 'https://child-safety-tracking-default-rtdb.firebaseio.com',
    storageBucket: 'child-safety-tracking.firebasestorage.app',
    iosBundleId: 'com.example.childTracker',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCZzfmyyuqFc_xw0Yp5DffmxfvS_heONN4',
    appId: '1:616084029405:web:21029b55c2620cc6674034',
    messagingSenderId: '616084029405',
    projectId: 'child-safety-tracking',
    databaseURL: 'https://child-safety-tracking-default-rtdb.firebaseio.com',
    storageBucket: 'child-safety-tracking.firebasestorage.app',
    iosBundleId: 'com.example.childTracker',
  );
}
