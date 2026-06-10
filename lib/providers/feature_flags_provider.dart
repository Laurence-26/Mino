import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the paid features (subscription gating, paywall, Customer Center)
/// are active. Backed by Firebase Remote Config key `paywall_enabled`.
///
/// Default: false → the app is completely free.
/// Flip to `true` in the Firebase console when you're ready to monetize;
/// no app release required.
final paywallEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval:
          kDebugMode ? Duration.zero : const Duration(hours: 1),
    ));
    await rc.setDefaults(const {'paywall_enabled': false});
    await rc.fetchAndActivate();
    return rc.getBool('paywall_enabled');
  } catch (e) {
    debugPrint('Remote Config error: $e — defaulting paywall to disabled');
    return false;
  }
});
