import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/feature_flags_provider.dart';
import 'package:pesa_tools/providers/subscription_provider.dart';
import 'package:pesa_tools/screens/splash_screen.dart';
import 'package:pesa_tools/services/notification_service.dart';
import 'package:pesa_tools/services/revenue_cat_service.dart';
import 'firebase_options.dart';
import 'providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await initializeDateFormatting();

  await NotificationService().initialize();

  runApp(
    const ProviderScope(
      child: MinoApp(),
    ),
  );
}

class MinoApp extends ConsumerWidget {
  const MinoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    ref.listen<AsyncValue<User?>>(authStateProvider, (_, next) async {
      final paywallOn =
          await ref.read(paywallEnabledProvider.future).catchError((_) => false);
      if (!paywallOn) return; // Free for everyone — skip RC entirely.

      final user = next.value;
      if (user == null) {
        await RevenueCatService().logOut();
      } else {
        await RevenueCatService().initialize(user.uid);
      }
      ref.invalidate(isPremiumProvider);
      ref.invalidate(packagesProvider);
    });

    return MaterialApp(
      title: 'Mino',
      debugShowCheckedModeBanner: false,

      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: Colors.grey[900],
        cardColor: Colors.grey[850],
      ),

      locale: locale,
      supportedLocales: AppTranslations.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const SplashScreen(),
    );
  }
}
