import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/providers/local_user_provider.dart';
import 'package:pesa_tools/screens/main_navigation.dart';

class StartingBalanceScreen extends ConsumerStatefulWidget {
  const StartingBalanceScreen({super.key});

  @override
  ConsumerState<StartingBalanceScreen> createState() => _StartingBalanceScreenState();
}

class _StartingBalanceScreenState extends ConsumerState<StartingBalanceScreen> {
  final _controller = TextEditingController(text: "0.00");

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
              AppTranslations.of(context, 'whats_your_starting_balance'),
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                hintText: "0.00",
              ),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () async {
                  final bal = double.tryParse(_controller.text) ?? 0.0;
                  await ref.read(localUserProvider.notifier).setStartingBalance(bal);
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const MainNavigation()),
                      (route) => false,
                    );
                  }
                },
                child: Text(
                  AppTranslations.of(context, 'finish_setup_and_go_to_dashboard'),
                  style: const TextStyle(fontSize: 18),
                ),
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