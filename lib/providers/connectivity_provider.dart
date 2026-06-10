import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the raw connectivity results whenever network state changes.
final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// True when at least one connectivity type is active (wifi, mobile, ethernet).
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityStreamProvider).when(
    data: (results) => results.any((r) => r != ConnectivityResult.none),
    loading: () => true, // assume online until proven otherwise
    error: (_, __) => true,
  );
});
