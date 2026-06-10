import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/models/group_model.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/group_provider.dart';
import 'package:pesa_tools/providers/firestore_provider.dart';
import 'package:pesa_tools/providers/export_provider.dart';
import 'package:pesa_tools/providers/feature_flags_provider.dart';
import 'package:pesa_tools/providers/subscription_provider.dart';
import 'package:pesa_tools/services/revenue_cat_service.dart';
import 'package:pesa_tools/widgets/transaction_tile.dart';
import 'package:pesa_tools/models/user_model.dart';
import 'package:pesa_tools/screens/transactions/add_transaction_screen.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _uuid = const Uuid();
  bool _isExporting = false;

  // Preload fonts (same approach as ReportsScreen)
  late final Future<pw.Font> _baseFont;
  late final Future<pw.Font> _boldFont;
  late final Future<pw.Font> _italicFont;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _baseFont = PdfGoogleFonts.openSansRegular();
    _boldFont = PdfGoogleFonts.openSansBold();
    _italicFont = PdfGoogleFonts.openSansItalic();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppTranslations.of(context, 'copiedToClipboard')
                .replaceFirst('{code}', text),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  DateTime _startOfWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  DateTime _startOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);
  DateTime _startOfYear(DateTime date) => DateTime(date.year, 1, 1);

  Map<String, double> _computeTotals(
      List<Transaction> transactions, DateTime start, DateTime end) {
    double income = 0.0, expense = 0.0;
    for (var t in transactions) {
      if (!t.date.isBefore(start) && !t.date.isAfter(end)) {
        if (t.type == TransactionType.income) {
          income += t.amount;
        } else {
          expense += t.amount;
        }
      }
    }
    return {'income': income, 'expense': expense, 'net': income - expense};
  }

  Map<String, dynamic> _getCategoryBreakdowns(List<Transaction> transactions) {
    final Map<String, double> incomeByCategory = {};
    final Map<String, double> expenseByCategory = {};
    double totalIncome = 0.0, totalExpense = 0.0;

    for (var t in transactions) {
      if (t.type == TransactionType.income) {
        incomeByCategory[t.category] =
            (incomeByCategory[t.category] ?? 0) + t.amount;
        totalIncome += t.amount;
      } else {
        expenseByCategory[t.category] =
            (expenseByCategory[t.category] ?? 0) + t.amount;
        totalExpense += t.amount;
      }
    }

    final sortedIncome = incomeByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedExpense = expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'incomeCategories': sortedIncome.map((e) => {
            'category': e.key,
            'amount': e.value,
            'percentage': totalIncome > 0
                ? (e.value / totalIncome * 100)
                : 0.0,
          }).toList(),
      'expenseCategories': sortedExpense.map((e) => {
            'category': e.key,
            'amount': e.value,
            'percentage': totalExpense > 0
                ? (e.value / totalExpense * 100)
                : 0.0,
          }).toList(),
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'netBalance': totalIncome - totalExpense,
    };
  }

  // ── UI: Activities tab (unchanged from original) ──
  Widget _buildActivitiesTab(List<Transaction> transactions, Group group) {
    final now = DateTime.now();
    final weekTotals = _computeTotals(transactions, _startOfWeek(now), now);
    final monthTotals = _computeTotals(transactions, _startOfMonth(now), now);
    final yearTotals = _computeTotals(transactions, _startOfYear(now), now);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildSummaryCard(
                  AppTranslations.of(context, 'thisWeek'), weekTotals),
              const SizedBox(width: 12),
              _buildSummaryCard(
                  AppTranslations.of(context, 'thisMonth'), monthTotals),
              const SizedBox(width: 12),
              _buildSummaryCard(
                  AppTranslations.of(context, 'thisYear'), yearTotals),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: transactions.isEmpty || _isExporting
                  ? null
                  : () => _handlePdfExport(transactions, group),  // gated export
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_isExporting
                  ? 'Exporting...'
                  : AppTranslations.of(context, 'exportPDF')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        Expanded(
          child: transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long,
                          size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        AppTranslations.of(context, 'noTransactions'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(
                        groupTransactionsStreamProvider(widget.groupId));
                  },
                  child: ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (ctx, index) {
                      final t = transactions[index];
                      return TransactionTile(
                        transaction: t,
                        groupId: widget.groupId,
                        onUpdated: () {
                          ref.invalidate(
                              groupTransactionsStreamProvider(widget.groupId));
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── Summary tab (unchanged) ──
  Widget _buildSummaryView(List<Transaction> transactions, Group group) {
    final breakdown = _getCategoryBreakdowns(transactions);
    final currency = NumberFormat.currency(symbol: '', decimalDigits: 2);
    final now = DateTime.now();
    final period = DateFormat('MMMM yyyy').format(now);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analysis Report',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Period: $period'),
            Text(
                'Generated on: ${DateFormat.yMMMd().add_jm().format(now)}'),
            const SizedBox(height: 16),
            const Divider(),
            Text('Financial Summary',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Table(
              border: TableBorder.all(color: Colors.grey.shade300),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(3),
              },
              children: [
                _buildTableRow('', 'Amount', isHeader: true),
                _buildTableRow(
                    'Total Income', currency.format(breakdown['totalIncome'])),
                _buildTableRow('Total Expenses',
                    currency.format(breakdown['totalExpense'])),
                _buildTableRow(
                    'Net Balance', currency.format(breakdown['netBalance']),
                    valueColor: (breakdown['netBalance'] as double) >= 0
                        ? Colors.green
                        : Colors.red),
              ],
            ),
            const SizedBox(height: 24),
            Text('Income Breakdown',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildCategoryTable(
              (breakdown['incomeCategories'] as List<dynamic>),
              currency,
              headerColor: Colors.green.shade100,
            ),
            const SizedBox(height: 24),
            Text('Expense Breakdown',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildCategoryTable(
              (breakdown['expenseCategories'] as List<dynamic>),
              currency,
              headerColor: Colors.red.shade100,
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildTableRow(String label, String value,
      {bool isHeader = false, Color? valueColor}) {
    return TableRow(
      decoration: isHeader
          ? BoxDecoration(color: Colors.grey.shade200)
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(label,
              style: TextStyle(
                  fontWeight:
                      isHeader ? FontWeight.bold : FontWeight.normal)),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(value,
              style: TextStyle(
                  fontWeight:
                      isHeader ? FontWeight.bold : FontWeight.normal,
                  color: valueColor),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Widget _buildCategoryTable(List<dynamic> categories, NumberFormat currency,
      {required Color headerColor}) {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade300),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: headerColor),
          children: const [
            Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Category',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Amount',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right)),
            Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('%',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right)),
          ],
        ),
        for (var cat in categories)
          TableRow(
            children: [
              Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(cat['category'])),
              Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(currency.format(cat['amount']),
                      textAlign: TextAlign.right)),
              Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                      '${(cat['percentage'] as double).toStringAsFixed(1)}%',
                      textAlign: TextAlign.right)),
            ],
          ),
      ],
    );
  }

  Widget _buildSummaryCard(String label, Map<String, double> totals) {
    final currency = NumberFormat.currency(symbol: '', decimalDigits: 0);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(
              '${AppTranslations.of(context, 'income')} ${currency.format(totals['income'])}',
              style: const TextStyle(fontSize: 12, color: Colors.green),
            ),
            Text(
              '${AppTranslations.of(context, 'expense')} ${currency.format(totals['expense'])}',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
            const Divider(height: 12),
            Text(
              '${AppTranslations.of(context, 'total')} ${currency.format(totals['net'])}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: totals['net']! >= 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PDF EXPORT GATE ────────────────────────────────────────────
  Future<void> _handlePdfExport(List<Transaction> transactions, Group group) async {
    final paywallEnabled = await ref.read(paywallEnabledProvider.future);
    if (!paywallEnabled) {
      await _exportPdf(transactions, group);
      return;
    }

    final isPremium = await ref.read(isPremiumProvider.future);
    if (isPremium) {
      await _exportPdf(transactions, group);
      return;
    }

    final exportsRemaining = ref.read(exportProvider);
    if (exportsRemaining > 0) {
      final used = await ref.read(exportProvider.notifier).useExport();
      if (used) {
        await _exportPdf(transactions, group);
        final remaining = ref.read(exportProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Export successful! $remaining free exports remaining'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
      return;
    }

    final unlocked = await RevenueCatService().requirePremium();
    if (!mounted) return;
    if (unlocked) {
      ref.invalidate(isPremiumProvider);
      await _exportPdf(transactions, group);
    }
  }

  // ── NEW: Clean PDF Layout (matching ReportsScreen style) ───────
  Future<void> _exportPdf(List<Transaction> transactions, Group group) async {
    if (transactions.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final baseFont = await _baseFont;
      final boldFont = await _boldFont;
      final italicFont = await _italicFont;

      final sorted = List<Transaction>.from(transactions)
        ..sort((a, b) => a.date.compareTo(b.date));

      // Totals
      final totalIncome = transactions
          .where((t) => t.type == TransactionType.income)
          .fold(0.0, (sum, t) => sum + t.amount);
      final totalExpense = transactions
          .where((t) => t.type == TransactionType.expense)
          .fold(0.0, (sum, t) => sum + t.amount);
      final net = totalIncome - totalExpense;

      // Category breakdowns
      final Map<String, double> incomeByCat = {};
      final Map<String, double> expenseByCat = {};
      for (var t in transactions) {
        if (t.type == TransactionType.income) {
          incomeByCat[t.category] = (incomeByCat[t.category] ?? 0) + t.amount;
        } else {
          expenseByCat[t.category] = (expenseByCat[t.category] ?? 0) + t.amount;
        }
      }

      final locale = Localizations.localeOf(context).toString();
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(group.name,
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('${AppTranslations.of(context, 'groupFinancialReport')}',
                  style: pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 4),
              pw.Text(
                  '${AppTranslations.of(context, 'generatedOn')}: ${DateFormat.yMMMd(locale).add_jm().format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.SizedBox(height: 12),
            ],
          ),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ),
          build: (_) => [
            // Financial Summary table
            pw.Text(AppTranslations.of(context, 'financialSummary'),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['', AppTranslations.of(context, 'amount')],
              data: [
                [AppTranslations.of(context, 'totalIncome'), formatCurrency(totalIncome)],
                [AppTranslations.of(context, 'totalExpenses'), formatCurrency(totalExpense)],
                [AppTranslations.of(context, 'netBalance'), formatCurrency(net)],
              ],
              border: null,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headerHeight: 30,
              cellHeight: 25,
              cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
            ),
            pw.SizedBox(height: 24),
            // Income Breakdown
            if (incomeByCat.isNotEmpty) ...[
              pw.Text(AppTranslations.of(context, 'incomeBreakdown'),
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: ['Category', 'Amount', '%'],
                data: incomeByCat.entries
                    .map((e) => [
                          e.key,
                          formatCurrency(e.value),
                          totalIncome > 0
                              ? '${(e.value / totalIncome * 100).toStringAsFixed(1)}%'
                              : '0%',
                        ])
                    .toList(),
                border: null,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                headerHeight: 30,
                cellHeight: 25,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 24),
            ],
            // Expense Breakdown
            if (expenseByCat.isNotEmpty) ...[
              pw.Text(AppTranslations.of(context, 'expenseBreakdown'),
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: ['Category', 'Amount', '%'],
                data: expenseByCat.entries
                    .map((e) => [
                          e.key,
                          formatCurrency(e.value),
                          totalExpense > 0
                              ? '${(e.value / totalExpense * 100).toStringAsFixed(1)}%'
                              : '0%',
                        ])
                    .toList(),
                border: null,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                headerHeight: 30,
                cellHeight: 25,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 24),
            ],
            // All Transactions
            pw.Text(AppTranslations.of(context, 'transactions'),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: [
                AppTranslations.of(context, 'date'),
                AppTranslations.of(context, 'category'),
                AppTranslations.of(context, 'description'),
                AppTranslations.of(context, 'type'),
                AppTranslations.of(context, 'amount'),
              ],
              data: sorted.map((t) => [
                    DateFormat.yMMMd(locale).format(t.date),
                    t.category,
                    t.description ?? '-',
                    t.type == TransactionType.income
                        ? AppTranslations.of(context, 'income')
                        : AppTranslations.of(context, 'expense'),
                    formatCurrency(t.amount),
                  ]).toList(),
              border: null,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headerHeight: 30,
              cellHeight: 25,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.center,
                4: pw.Alignment.centerRight,
              },
            ),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final fileName = 'Mino_${group.name}_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: '${group.name} — Group Financial Report',
        );
      }
    } catch (e) {
      debugPrint('PDF export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppTranslations.of(context, 'error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // Helper for currency formatting in PDF (same as in ReportsScreen)
  String formatCurrency(double amount) {
    final fmt = NumberFormat.currency(symbol: '', decimalDigits: 2);
    return fmt.format(amount);
  }

  void _showAddTransactionDialog(BuildContext context, String groupId) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(groupId: groupId),
      ),
    );
  }

  Future<void> _editGroupName(Group group) async {
    if (!mounted) return;
    final controller = TextEditingController(text: group.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1625),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppTranslations.of(context, 'editGroupName'),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Group name',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppTranslations.of(context, 'cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(ctx, value);
            },
            child: Text(AppTranslations.of(context, 'save')),
          ),
        ],
      ),
    );

    if (newName == null || newName == group.name) return;

    try {
      await ref
          .read(firestoreServiceProvider)
          .updateGroupName(group.id, newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group name updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  Future<void> _leaveGroup(Group group, String userId) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1625),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppTranslations.of(context, 'leaveGroup'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to leave "${group.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.of(context, 'cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(AppTranslations.of(context, 'leaveGroup')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(firestoreServiceProvider).leaveGroup(group.id, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Left "${group.name}"')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to leave: $e')),
        );
      }
    }
  }

  Future<void> _deleteGroup(Group group) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1625),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppTranslations.of(context, 'deleteGroup'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'Permanently delete "${group.name}"? All transactions in this group will be lost. This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.of(context, 'cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(AppTranslations.of(context, 'deleteGroup')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(firestoreServiceProvider).deleteGroup(group.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${group.name}"')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(Group group, AppUser member) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1625),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove member',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove ${member.displayName ?? member.email} from "${group.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.of(context, 'cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(firestoreServiceProvider)
          .removeMember(group.id, member.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Removed ${member.displayName ?? member.email}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupStreamProvider(widget.groupId));
    final userRoleAsync = ref.watch(userGroupRoleProvider(widget.groupId));
    final transactionsAsync =
        ref.watch(groupTransactionsStreamProvider(widget.groupId));
    final membersAsync =
        ref.watch(groupMembersStreamProvider(widget.groupId));
    final currentUser = ref.watch(currentUserProvider).value;
    final exportsRemaining = ref.watch(exportProvider);
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final paywallEnabled = ref.watch(paywallEnabledProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: groupAsync.when(
          data: (group) => Text(group?.name ?? ''),
          loading: () => Text(AppTranslations.of(context, 'loading')),
          error: (e, _) => Text(AppTranslations.of(context, 'error')),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: AppTranslations.of(context, 'activities')),
            Tab(text: AppTranslations.of(context, 'members')),
            Tab(text: AppTranslations.of(context, 'summary')),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              final group = groupAsync.asData?.value;
              if (group == null || currentUser == null) return;
              if (value == 'edit') {
                _editGroupName(group);
              } else if (value == 'leave') {
                _leaveGroup(group, currentUser.uid);
              } else if (value == 'delete') {
                _deleteGroup(group);
              }
            },
            itemBuilder: (ctx) {
              final group = groupAsync.asData?.value;
              final isAdmin = group != null &&
                  currentUser != null &&
                  group.members[currentUser.uid] == GroupRole.admin;
              return [
                if (isAdmin)
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit),
                        const SizedBox(width: 8),
                        Text(AppTranslations.of(context, 'editGroupName')),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      const Icon(Icons.exit_to_app, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(AppTranslations.of(context, 'leaveGroup')),
                    ],
                  ),
                ),
                if (isAdmin)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(AppTranslations.of(context, 'deleteGroup')),
                      ],
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
      body: groupAsync.when(
        data: (group) {
          if (group == null) {
            return Center(
              child: Text(AppTranslations.of(context, 'groupNotFound')),
            );
          }

          return Column(
            children: [
              // ── Export Status Banner — only when monetization is on. ──
              if (paywallEnabled)
                isPremiumAsync.when(
                data: (isPremium) {
                  if (isPremium) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.shade700, Colors.orange.shade700],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.workspace_premium, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            '💎 Premium — Unlimited Exports',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade700),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          '$exportsRemaining free PDF exports remaining',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Invite code banner
              if (group.inviteCode != null && group.inviteCode!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppTranslations.of(context, 'inviteCode'),
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            Text(group.inviteCode!,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.blue),
                        onPressed: () => _copyToClipboard(group.inviteCode!),
                        tooltip: AppTranslations.of(context, 'copyInviteCode'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    transactionsAsync.when(
                      data: (transactions) =>
                          _buildActivitiesTab(transactions, group),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text('${AppTranslations.of(context, 'error')}: $e')),
                    ),
                    membersAsync.when(
                      data: (members) {
                        if (members.isEmpty) {
                          return Center(
                            child: Text(
                              AppTranslations.of(context, 'noMembers'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          );
                        }
                        final isAdmin = currentUser != null &&
                            group.members[currentUser.uid] == GroupRole.admin;
                        return RefreshIndicator(
                          onRefresh: () async {
                            ref.invalidate(
                              groupMembersStreamProvider(widget.groupId),
                            );
                          },
                          child: ListView.builder(
                            itemCount: members.length,
                            itemBuilder: (ctx, index) {
                              final member = members[index];
                              final role = group.members[member.uid];
                              final isSelf =
                                  currentUser != null && member.uid == currentUser.uid;
                              final canRemove = isAdmin && !isSelf;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: member.photoUrl != null
                                      ? NetworkImage(member.photoUrl!)
                                      : null,
                                  child: member.photoUrl == null
                                      ? Text(
                                          (member.displayName?.isNotEmpty == true
                                                  ? member.displayName!
                                                  : (member.email.isNotEmpty
                                                      ? member.email
                                                      : '?'))
                                              .substring(0, 1)
                                              .toUpperCase(),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  member.displayName?.isNotEmpty == true
                                      ? member.displayName!
                                      : (member.email.isNotEmpty
                                          ? member.email
                                          : member.uid),
                                ),
                                subtitle: Text(
                                  role != null
                                      ? '${role.name[0].toUpperCase()}${role.name.substring(1)}${isSelf ? " · You" : ""}'
                                      : (isSelf ? 'You' : ''),
                                ),
                                trailing: canRemove
                                    ? IconButton(
                                        icon: const Icon(Icons.person_remove,
                                            color: Colors.red),
                                        tooltip: 'Remove member',
                                        onPressed: () =>
                                            _removeMember(group, member),
                                      )
                                    : null,
                              );
                            },
                          ),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text('${AppTranslations.of(context, 'error')}: $e')),
                    ),
                    transactionsAsync.when(
                      data: (transactions) =>
                          _buildSummaryView(transactions, group),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text('Error: $e')),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => Center(child: Text(AppTranslations.of(context, 'loading'))),
        error: (e, _) =>
            Center(child: Text('${AppTranslations.of(context, 'error')}: $e')),
      ),
      floatingActionButton: userRoleAsync.when(
        data: (role) {
          if (role == GroupRole.admin || role == GroupRole.editor) {
            return FloatingActionButton(
              onPressed: () => _showAddTransactionDialog(context, widget.groupId),
              child: const Icon(Icons.add),
            );
          }
          return null;
        },
        loading: () => null,
        error: (_, __) => null,
      ),
    );
  }
}