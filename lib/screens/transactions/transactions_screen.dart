import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:printing/printing.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/providers/transaction_provider.dart';
import 'package:pesa_tools/widgets/transaction_tile.dart';
import 'package:pesa_tools/widgets/offline_banner.dart';
import 'add_transaction_screen.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeFilter = ref.watch(transactionFilterProvider);
    final timePeriod = ref.watch(timePeriodProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final transactions = ref.watch(filteredTransactionsByPeriodProvider);

    final dateLabel = _getDateRangeLabel(context, selectedDate, timePeriod);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    double totalIncome = 0;
    double totalExpense = 0;
    for (var t in transactions) {
      if (t.type == TransactionType.income) {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          AppTranslations.of(context, 'transactions'),
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showFilterBottomSheet(context, ref, typeFilter),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _generatePdf(context, transactions, dateLabel),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          _buildDateNavigation(context, ref, selectedDate, timePeriod, dateLabel),
          _buildPeriodSelector(context, ref, timePeriod),
          const SizedBox(height: 12),
          _buildSummarySection(context, totalIncome, totalExpense),
          const SizedBox(height: 20),
          _buildTransactionList(context, ref, transactions),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
        ),
        icon: const Icon(Icons.add),
        label: Text(AppTranslations.of(context, 'addTransaction')),
      ),
    );
  }

  // ── DATE NAVIGATION ────────────────────────────────────────────────────────
  Widget _buildDateNavigation(
      BuildContext context,
      WidgetRef ref,
      DateTime selectedDate,
      TimePeriod period,
      String dateLabel,
      ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref.read(selectedDateProvider.notifier).state =
                  _changeDate(selectedDate, period, false);
            },
          ),
          Expanded(
            child: Text(
              dateLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              ref.read(selectedDateProvider.notifier).state =
                  _changeDate(selectedDate, period, true);
            },
          ),
        ],
      ),
    );
  }

  DateTime _changeDate(DateTime current, TimePeriod period, bool forward) {
    switch (period) {
      case TimePeriod.week:
        return current.add(Duration(days: forward ? 7 : -7));
      case TimePeriod.month:
        return DateTime(current.year, current.month + (forward ? 1 : -1), 1);
      case TimePeriod.quarter:
        return DateTime(current.year, current.month + (forward ? 3 : -3), 1);
      case TimePeriod.year:
        return DateTime(current.year + (forward ? 1 : -1), 1);
    }
  }

  // ── PERIOD SELECTOR ────────────────────────────────────────────────────────
  Widget _buildPeriodSelector(BuildContext context, WidgetRef ref, TimePeriod current) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: TimePeriod.values.map((period) {
        final selected = period == current;
        return GestureDetector(
          onTap: () => ref.read(timePeriodProvider.notifier).state = period,
          child: Text(
            AppTranslations.of(context, period.name),
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── SUMMARY ────────────────────────────────────────────────────────────────
  Widget _buildSummarySection(BuildContext context, double income, double expense) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _summaryCard(
                context, AppTranslations.of(context, 'income'), income, Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _summaryCard(
                context, AppTranslations.of(context, 'expense'), expense, Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16), color: color.withOpacity(0.1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 8),
          Text(amount.toStringAsFixed(2), style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  // ── TRANSACTION LIST ───────────────────────────────────────────────────────
  Widget _buildTransactionList(
      BuildContext context, WidgetRef ref, List<Transaction> transactions) {
    if (transactions.isEmpty) {
      return Expanded(
        child: Center(child: Text(AppTranslations.of(context, 'noTransactionsYet'))),
      );
    }

    return Expanded(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(transactionsStreamProvider);
          ref.invalidate(filteredTransactionsByPeriodProvider);
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) => TransactionTile(
            transaction: transactions[index],
            onUpdated: () {
              ref.invalidate(transactionsStreamProvider);
              ref.invalidate(filteredTransactionsByPeriodProvider);
            },
          ),
        ),
      ),
    );
  }

  // ── FILTER ─────────────────────────────────────────────────────────────────
  Future<void> _showFilterBottomSheet(
      BuildContext context,
      WidgetRef ref,
      TransactionFilter currentFilter,
      ) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppTranslations.of(context, 'filterTransactions'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ...TransactionFilter.values.map((filter) {
                return RadioListTile<TransactionFilter>(
                  value: filter,
                  groupValue: currentFilter,
                  title: Text(filter.name.toUpperCase()),
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(transactionFilterProvider.notifier).state = value;
                      Navigator.pop(context);
                    }
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  // ── DATE LABEL ─────────────────────────────────────────────────────────────
  String _getDateRangeLabel(BuildContext context, DateTime date, TimePeriod period) {
    final locale = Localizations.localeOf(context).toString();
    switch (period) {
      case TimePeriod.week:
        final start = date.subtract(Duration(days: date.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return '${DateFormat.yMMMd(locale).format(start)} – ${DateFormat.yMMMd(locale).format(end)}';
      case TimePeriod.month:
        return DateFormat.yMMMM(locale).format(date);
      case TimePeriod.quarter:
        final quarterStartMonth = ((date.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(date.year, quarterStartMonth, 1);
        final end = DateTime(date.year, quarterStartMonth + 2, 1);
        return '${DateFormat.MMM(locale).format(start)} – ${DateFormat.MMMM(locale).format(end)} ${date.year}';
      case TimePeriod.year:
        return date.year.toString();
    }
  }

  // ── PDF ────────────────────────────────────────────────────────────────────
  Future<void> _generatePdf(
      BuildContext context,
      List<Transaction> transactions,
      String periodLabel,
      ) async {
    if (transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTranslations.of(context, 'noTransactionsToExport'))),
      );
      return;
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('Transaction Report – $periodLabel',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            headers: ['Date', 'Category', 'Description', 'Amount'],
            data: transactions.map((t) {
              return [
                DateFormat('dd/MM/yyyy').format(t.date),
                t.category,
                t.description ?? '',
                '${t.type == TransactionType.income ? '+' : '-'}${t.amount.toStringAsFixed(2)}',
              ];
            }).toList(),
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'transactions_${periodLabel.replaceAll(' ', '_')}.pdf',
    );
  }
}
