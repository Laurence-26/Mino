import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/providers/local_user_provider.dart';

import 'starting_balance_screen.dart';

class NameSetupScreen extends ConsumerStatefulWidget {
  const NameSetupScreen({super.key});

  @override
  ConsumerState<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends ConsumerState<NameSetupScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            Text(
              AppTranslations.of(context, 'welcome'),
              style: Theme.of(context).textTheme.headlineLarge!.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              AppTranslations.of(context, 'whats_your_name'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: AppTranslations.of(context, 'your_name'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
              style: const TextStyle(fontSize: 22),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () async {
                  if (_controller.text.trim().isEmpty) return;
                  await ref.read(localUserProvider.notifier).setName(_controller.text.trim());
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const StartingBalanceScreen()),
                    );
                  }
                },
                child: Text(AppTranslations.of(context, 'continue')),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}