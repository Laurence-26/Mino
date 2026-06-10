import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/providers/connectivity_provider.dart';

/// A slim animated banner that appears whenever the device goes offline.
/// Drop it at the top of any Scaffold body Column.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: isOnline
          ? const SizedBox.shrink()
          : Container(
        width: double.infinity,
        color: Colors.orange.shade800,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 15, color: Colors.white),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'You\'re offline — your changes will sync when connected',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
