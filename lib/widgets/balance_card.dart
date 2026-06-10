import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../110n/app_translations.dart'; // adjust path if needed
import '../utils/currency_formatter.dart';

class BalanceCard extends ConsumerWidget {
  final double balance;
  final double income;
  final double expenses;
  final VoidCallback? onAddIncome;
  final VoidCallback? onAddExpense;

  const BalanceCard({
    super.key,
    required this.balance,
    required this.income,
    required this.expenses,
    this.onAddIncome,
    this.onAddExpense,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTranslations.of(context, 'currentBalance'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              formatCurrency(balance),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        AppTranslations.of(context, 'totalIncome'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        formatCurrency(income),
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        AppTranslations.of(context, 'totalExpenses'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        formatCurrency(expenses),
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAddIncome,
                    icon: const Icon(Icons.add),
                    label: Text(AppTranslations.of(context, 'addIncome')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAddExpense,
                    icon: const Icon(Icons.remove),
                    label: Text(AppTranslations.of(context, 'addExpense')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}