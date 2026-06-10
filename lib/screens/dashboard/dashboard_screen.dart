import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/providers/settings_provider.dart';
import 'package:pesa_tools/providers/transaction_provider.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/feature_flags_provider.dart';
import 'package:pesa_tools/providers/subscription_provider.dart';
import 'package:pesa_tools/services/revenue_cat_service.dart';

import '../../widgets/balance_card.dart';
import '../../widgets/transaction_tile.dart';
import '../auth/register_screen.dart';
import '../transactions/add_transaction_screen.dart';
import '../auth/login_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final userAsync = ref.watch(currentUserProvider);
    final paywallEnabled = ref.watch(paywallEnabledProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mino'),
        actions: [
          // Language switcher
          PopupMenuButton<Locale>(
            icon: const Icon(Icons.language),
            onSelected: (Locale newLocale) {
              ref.read(localeProvider.notifier).state = newLocale;
            },
            itemBuilder: (context) {
              final supportedLocales = AppTranslations.supportedLocales;
              final currentLocale = ref.read(localeProvider);
              return supportedLocales.map((locale) {
                return PopupMenuItem<Locale>(
                  value: locale,
                  child: Row(
                    children: [
                      if (currentLocale.languageCode == locale.languageCode)
                        const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Text(_getLanguageName(locale.languageCode, context)),
                    ],
                  ),
                );
              }).toList();
            },
          ),

          // Settings menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) async {
              switch (value) {
                case 'manage_subscription':
                  await RevenueCatService().presentCustomerCenter();
                  ref.invalidate(isPremiumProvider);
                  break;

                case 'delete_account':
                  await _handleDeleteAccount(context, ref);
                  break;

                case 'logout':
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(AppTranslations.of(context, 'logout')),
                      content: Text(
                          AppTranslations.of(context, 'logout_confirmation')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(AppTranslations.of(context, 'cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(AppTranslations.of(context, 'logout')),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && context.mounted) {
                    try {
                      await ref.read(authServiceProvider).signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '${AppTranslations.of(context, 'error')}: $e')),
                        );
                      }
                    }
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              if (paywallEnabled)
                const PopupMenuItem(
                  value: 'manage_subscription',
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium, size: 20),
                      SizedBox(width: 12),
                      Text('Manage Subscription'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'delete_account',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Delete Account',
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout, size: 20),
                    const SizedBox(width: 12),
                    Text(AppTranslations.of(context, 'logout')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      body: transactionsAsync.when(
        data: (transactions) {
          final totalIncome = transactions
              .where((t) => t.type == TransactionType.income)
              .fold(0.0, (sum, t) => sum + t.amount);

          final totalExpense = transactions
              .where((t) => t.type == TransactionType.expense)
              .fold(0.0, (sum, t) => sum + t.amount);

          final netBalance = totalIncome - totalExpense;

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: userAsync.when(
                  data: (appUser) {
                    final authUser = FirebaseAuth.instance.currentUser;
                    final rawName = (appUser?.displayName?.isNotEmpty == true)
                        ? appUser!.displayName
                        : (authUser?.displayName?.isNotEmpty == true
                            ? authUser!.displayName
                            : null);
                    final displayName = rawName?.split(' ').first ??
                        AppTranslations.of(context, 'user');
                    return Text(
                      '${AppTranslations.of(context, 'welcome')}, $displayName!',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => Text(
                    '${AppTranslations.of(context, 'welcome')}!',
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                ),
              ),

              BalanceCard(
                balance: netBalance,
                income: totalIncome,
                expenses: totalExpense,
                onAddIncome: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddTransactionScreen(
                        initialType: TransactionType.income),
                  ),
                ),
                onAddExpense: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddTransactionScreen(
                        initialType: TransactionType.expense),
                  ),
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppTranslations.of(context, 'recent_transactions'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text(AppTranslations.of(context, 'view_all')),
                    ),
                  ],
                ),
              ),

              ...transactions.take(5).map((t) => TransactionTile(transaction: t)),

              if (transactions.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        AppTranslations.of(context, 'noTransactionsYet')),
                  ),
                ),
            ],
          );
        },
        error: (error, stack) => Center(
          child: Text('${AppTranslations.of(context, 'error')}: $error'),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _handleDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).value;
    final isGoogle =
        user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?',
            style: TextStyle(color: Colors.red)),
        content: const Text(
          'This action is PERMANENT.\n\nAll your transactions and data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
    if (confirmDelete != true) return;

    String password = '';

    // Only ask for password if email/password provider
    if (!isGoogle) {
      final passwordController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your password to confirm:'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('DELETE'),
            ),
          ],
        ),
      );
      password = passwordController.text.trim();
      passwordController.dispose();
      if (confirmed != true || password.isEmpty) return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(authServiceProvider).deleteAccount(password);
      if (context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RegisterScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  String _getLanguageName(String code, BuildContext context) {
    switch (code) {
      case 'en':
        return AppTranslations.of(context, 'english') ?? 'English';
      case 'sw':
        return AppTranslations.of(context, 'kiswahili') ?? 'Kiswahili';
      case 'fr':
        return AppTranslations.of(context, 'francais') ?? 'Français';
      default:
        return code;
    }
  }
}
