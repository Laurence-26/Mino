import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/providers/settings_provider.dart';

import 'name_setup_screen.dart';

class LanguageSelectionScreen extends ConsumerWidget {
  const LanguageSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Text(
                  AppTranslations.of(context, 'choose_language'),
                  style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppTranslations.of(context, 'choose_language_subtitle'),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                _LanguageCard(
                  flag: "🇬🇧",
                  name: "English",
                  locale: const Locale('en'),
                  current: locale,
                  onTap: () => ref.read(localeProvider.notifier).state = const Locale('en'),
                ),
                const SizedBox(height: 12),
                _LanguageCard(
                  flag: "🇹🇿",
                  name: "Kiswahili",
                  locale: const Locale('sw'),
                  current: locale,
                  onTap: () => ref.read(localeProvider.notifier).state = const Locale('sw'),
                ),
                const SizedBox(height: 12),
                _LanguageCard(
                  flag: "🇫🇷",
                  name: "Français",
                  locale: const Locale('fr'),
                  current: locale,
                  onTap: () => ref.read(localeProvider.notifier).state = const Locale('fr'),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const NameSetupScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue.shade900,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      AppTranslations.of(context, 'continue'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final String flag;
  final String name;
  final Locale locale;
  final Locale current;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.flag,
    required this.name,
    required this.locale,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = locale.languageCode == current.languageCode;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: Colors.white, width: 3) : null,
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 40)),
            const SizedBox(width: 20),
            Text(
              name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.blue.shade900 : Colors.white,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 28,
              ),
          ],
        ),
      ),
    );
  }
}