import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart'
    hide Column, Alignment, Row, Border;
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/providers/export_provider.dart';
import 'package:pesa_tools/providers/feature_flags_provider.dart';
import 'package:pesa_tools/providers/subscription_provider.dart';
import 'package:pesa_tools/services/revenue_cat_service.dart';
import '../../providers/transaction_provider.dart';
import '../../utils/currency_formatter.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _selectedRange = 'All Time';
  bool _isExporting = false;
  late final Future<pw.Font> _baseFont;
  late final Future<pw.Font> _boldFont;

  @override
  void initState() {
    super.initState();
    _baseFont = PdfGoogleFonts.openSansRegular();
    _boldFont = PdfGoogleFonts.openSansBold();
  }

  DateTime get _startDate {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 'This Month':
        return DateTime(now.year, now.month, 1);
      case 'This Quarter':
        int quarterMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTime(now.year, quarterMonth, 1);
      case 'This Year':
        return DateTime(now.year, 1, 1);
      case 'All Time':
      default:
        return DateTime(2000, 1, 1);
    }
  }

  DateTime get _endDate {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 'All Time':
        return DateTime(2100, 1, 1);
      case 'This Month':
        return DateTime(now.year, now.month + 1, 0);
      case 'This Quarter':
        int quarterMonth = ((now.month - 1) ~/ 3) * 3 + 3;
        return DateTime(now.year, quarterMonth + 1, 0);
      case 'This Year':
        return DateTime(now.year + 1, 1, 0);
      default:
        return DateTime.now();
    }
  }

  List<Transaction> _filterTransactions(List<Transaction> transactions) {
    return transactions.where((t) {
      return t.date.isAfter(
              _startDate.subtract(const Duration(days: 1))) &&
          t.date.isBefore(_endDate.add(const Duration(days: 1)));
    }).toList();
  }

  String _getTranslatedRange() {
    return AppTranslations.of(
        context, _selectedRange.toLowerCase().replaceAll(' ', ''));
  }

  // ── HANDLE PDF EXPORT WITH SUBSCRIPTION GATE ───────────────────
  Future<void> _handlePdfExport(List<Transaction> transactions) async {
    final paywallEnabled = await ref.read(paywallEnabledProvider.future);
    if (!paywallEnabled) {
      await _exportPDF(transactions);
      return;
    }

    final isPremium = await ref.read(isPremiumProvider.future);
    if (isPremium) {
      await _exportPDF(transactions);
      return;
    }

    final exportsRemaining = ref.read(exportProvider);
    if (exportsRemaining > 0) {
      final used = await ref.read(exportProvider.notifier).useExport();
      if (used) {
        await _exportPDF(transactions);
        final remaining = ref.read(exportProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Export successful! $remaining free exports remaining'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
      return;
    }

    // No credits left → present hosted paywall.
    final unlocked = await RevenueCatService().requirePremium();
    if (!mounted) return;
    if (unlocked) {
      ref.invalidate(isPremiumProvider);
      await _exportPDF(transactions);
    }
  }


  @override
  Widget build(BuildContext context) {
    final allTransactions =
        ref.watch(transactionsStreamProvider).value ?? [];
    final transactions = _filterTransactions(allTransactions);

    final totalIncome = _totalIncome(transactions);
    final totalExpense = _totalExpense(transactions);
    final balance = totalIncome - totalExpense;

    // Watch exports remaining for UI
    final exportsRemaining = ref.watch(exportProvider);
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final paywallEnabled = ref.watch(paywallEnabledProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.of(context, 'reports')),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) =>
                setState(() => _selectedRange = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'This Month',
                  child: Text(
                      AppTranslations.of(context, 'thisMonth'))),
              PopupMenuItem(
                  value: 'This Quarter',
                  child: Text(
                      AppTranslations.of(context, 'thisQuarter'))),
              PopupMenuItem(
                  value: 'This Year',
                  child: Text(
                      AppTranslations.of(context, 'thisYear'))),
              PopupMenuItem(
                  value: 'All Time',
                  child:
                      Text(AppTranslations.of(context, 'allTime'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Premium/Export status banner — only when monetization is on.
          if (paywallEnabled)
            isPremiumAsync.when(
            data: (isPremium) {
              if (isPremium) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade700,
                        Colors.orange.shade700
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.workspace_premium,
                          color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        '💎 Premium — Unlimited Exports',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade700),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf,
                        color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      '$exportsRemaining free PDF exports remaining',
                      style: const TextStyle(color: Colors.blue),
                    ),
                    const Spacer(),
                    if (exportsRemaining == 0)
                      TextButton(
                        onPressed: () async {
                          final unlocked =
                              await RevenueCatService().requirePremium();
                          if (unlocked) {
                            ref.invalidate(isPremiumProvider);
                          }
                        },
                        child: const Text('Get More'),
                      ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    AppTranslations.of(context, 'financialSummary'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                      AppTranslations.of(context, 'totalIncome'),
                      totalIncome,
                      Colors.green),
                  _buildSummaryRow(
                      AppTranslations.of(context, 'totalExpenses'),
                      totalExpense,
                      Colors.red),
                  _buildSummaryRow(
                      AppTranslations.of(context, 'cashBalance'),
                      balance,
                      Colors.blue),
                  const Divider(),
                  _buildSummaryRow(
                      AppTranslations.of(context, 'netBalance'),
                      balance,
                      Colors.black),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            AppTranslations.of(context, 'monthlyOverview'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _buildMonthlyTextOverview(transactions),
          const SizedBox(height: 24),

          // Export card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppTranslations.of(context, 'exportReport'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      // PDF — with ads/subscription gate
                      ElevatedButton.icon(
                        onPressed: _isExporting
                            ? null
                            : () => _handlePdfExport(transactions),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: _isExporting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text(AppTranslations.of(
                                context, 'pdf')),
                      ),
                      // Excel — free
                      ElevatedButton.icon(
                        onPressed: _isExporting
                            ? null
                            : () => _exportExcel(transactions),
                        icon: const Icon(Icons.table_chart),
                        label: _isExporting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text(AppTranslations.of(
                                context, 'excel')),
                      ),
                      // CSV — free
                      ElevatedButton.icon(
                        onPressed: _isExporting
                            ? null
                            : () => _exportCSV(transactions),
                        icon: const Icon(Icons.insert_drive_file),
                        label: _isExporting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text(AppTranslations.of(
                                context, 'csv')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
      String label, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            formatCurrency(amount),
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTextOverview(
      List<Transaction> transactions) {
    final monthlyData = _monthlySummaryData(transactions);
    if (monthlyData.isEmpty) return const SizedBox.shrink();

    final years =
        monthlyData.map((e) => (e['monthDate'] as DateTime).year).toSet();
    final bool multiYear = years.length > 1;
    final String pattern = multiYear ? 'MMMM yyyy' : 'MMMM';
    final String locale =
        Localizations.localeOf(context).toString();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: monthlyData.length,
      itemBuilder: (context, index) {
        final data = monthlyData[index];
        final income = data['income'] as double;
        final expense = data['expense'] as double;
        final total = data['total'] as double;
        final monthDate = data['monthDate'] as DateTime;
        final monthName =
            DateFormat(pattern, locale).format(monthDate);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text(monthName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(
                      '${AppTranslations.of(context, 'total')}: ${formatCurrency(total)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${AppTranslations.of(context, 'income')}: ${formatCurrency(income)}',
                      style:
                          const TextStyle(color: Colors.green),
                    ),
                    Text(
                      '${AppTranslations.of(context, 'expense')}: ${formatCurrency(expense)}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Export Helpers ────────────────────────────────────────────

  Future<void> _exportPDF(List<Transaction> transactions) async {
    if (transactions.isEmpty) return;
    setState(() => _isExporting = true);

    try {
      final baseFont = await _baseFont;
      final boldFont = await _boldFont;

      final sortedTransactions =
          List<Transaction>.from(transactions)
            ..sort((a, b) => a.date.compareTo(b.date));

      final monthlyData = _monthlySummaryData(transactions);
      final years = monthlyData
          .map((e) => (e['monthDate'] as DateTime).year)
          .toSet();
      final bool multiYear = years.length > 1;
      final String pattern = multiYear ? 'MMMM yyyy' : 'MMMM';
      final String locale =
          Localizations.localeOf(context).toString();

      final pdf = pw.Document(
          theme: pw.ThemeData.withFont(
              base: baseFont, bold: boldFont));

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (_) => pw.Column(
            children: [
              pw.Text(
                AppTranslations.of(context, 'transactionReport')
                    .replaceAll('{period}', _getTranslatedRange()),
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${AppTranslations.of(context, 'generatedOn')}: ${DateFormat.yMMMd(locale).add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 12),
            ],
          ),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
                'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey)),
          ),
          build: (_) => [
            pw.Text(
                AppTranslations.of(context, 'financialSummary'),
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: [
                AppTranslations.of(context, 'description'),
                AppTranslations.of(context, 'amount')
              ],
              data: [
                [
                  AppTranslations.of(context, 'totalIncome'),
                  formatCurrency(_totalIncome(transactions))
                ],
                [
                  AppTranslations.of(context, 'totalExpenses'),
                  formatCurrency(_totalExpense(transactions))
                ],
                [
                  AppTranslations.of(context, 'netBalance'),
                  formatCurrency(_balance(transactions))
                ],
              ],
              border: null,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headerHeight: 30,
              cellHeight: 25,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight
              },
            ),
            pw.SizedBox(height: 24),
            pw.Text(
                AppTranslations.of(context, 'transactions'),
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: [
                AppTranslations.of(context, 'date'),
                AppTranslations.of(context, 'category'),
                AppTranslations.of(context, 'description'),
                AppTranslations.of(context, 'type'),
                AppTranslations.of(context, 'amount'),
              ],
              data: sortedTransactions
                  .map((t) => [
                        DateFormat.yMMMd(locale).format(t.date),
                        t.category,
                        t.description ??
                            AppTranslations.of(
                                context, 'noDescription'),
                        t.type == TransactionType.income
                            ? AppTranslations.of(
                                context, 'income')
                            : AppTranslations.of(
                                context, 'expense'),
                        formatCurrency(t.amount),
                      ])
                  .toList(),
              border: null,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
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

      final dir = await _getExportDirectory();
      final fileName =
          'Mino_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: 'Pesa Tools Financial Report',
        );
      }
    } catch (e, st) {
      debugPrint('PDF export error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${AppTranslations.of(context, 'error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportExcel(
      List<Transaction> transactions) async {
    setState(() => _isExporting = true);
    try {
      final Workbook workbook = Workbook();
      final sortedTransactions =
          List<Transaction>.from(transactions)
            ..sort((a, b) => a.date.compareTo(b.date));
      final String locale =
          Localizations.localeOf(context).toString();

      final Worksheet transSheet = workbook.worksheets[0];
      transSheet.name =
          AppTranslations.of(context, 'transactions');

      transSheet
          .getRangeByIndex(1, 1)
          .setText(AppTranslations.of(context, 'date'));
      transSheet
          .getRangeByIndex(1, 2)
          .setText(AppTranslations.of(context, 'category'));
      transSheet
          .getRangeByIndex(1, 3)
          .setText(AppTranslations.of(context, 'description'));
      transSheet
          .getRangeByIndex(1, 4)
          .setText(AppTranslations.of(context, 'type'));
      transSheet
          .getRangeByIndex(1, 5)
          .setText(AppTranslations.of(context, 'amount'));

      final Style headerStyle = workbook.styles.add('Header');
      headerStyle.bold = true;
      headerStyle.backColor = '#E0E0E0';
      transSheet.getRangeByName('A1:E1').cellStyle = headerStyle;

      for (int i = 0; i < sortedTransactions.length; i++) {
        final t = sortedTransactions[i];
        final int row = i + 2;
        transSheet.getRangeByIndex(row, 1).setText(
            DateFormat.yMMMd(locale).format(t.date));
        transSheet.getRangeByIndex(row, 2).setText(t.category);
        transSheet.getRangeByIndex(row, 3).setText(t.description ??
            AppTranslations.of(context, 'noDescription'));
        transSheet.getRangeByIndex(row, 4).setText(
            t.type == TransactionType.income
                ? AppTranslations.of(context, 'income')
                : AppTranslations.of(context, 'expense'));
        transSheet
            .getRangeByIndex(row, 5)
            .setNumber(t.amount);
        transSheet.getRangeByIndex(row, 5).numberFormat =
            '#,##0.00';
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await _getExportDirectory();
      final fileName =
          'Mino_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        await Share.shareXFiles(
          [
            XFile(file.path,
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
          ],
          text: 'Pesa Tools Financial Report',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${AppTranslations.of(context, 'error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportCSV(List<Transaction> transactions) async {
    setState(() => _isExporting = true);
    try {
      final sortedTransactions =
          List<Transaction>.from(transactions)
            ..sort((a, b) => a.date.compareTo(b.date));
      final String locale =
          Localizations.localeOf(context).toString();

      final buffer = StringBuffer();
      buffer.write('\uFEFF');
      buffer.writeln(
          '"${AppTranslations.of(context, 'transactionReport').replaceAll('{period}', _getTranslatedRange())}"');
      buffer.writeln(
          '"${AppTranslations.of(context, 'generatedOn')}: ${DateFormat.yMMMd(locale).add_jm().format(DateTime.now())}"');
      buffer.writeln();
      buffer.writeln(
          '"${AppTranslations.of(context, 'financialSummary')}"');
      buffer.writeln(
          '"${AppTranslations.of(context, 'totalIncome')}",${_totalIncome(transactions).toStringAsFixed(2)}');
      buffer.writeln(
          '"${AppTranslations.of(context, 'totalExpenses')}",${_totalExpense(transactions).toStringAsFixed(2)}');
      buffer.writeln(
          '"${AppTranslations.of(context, 'netBalance')}",${_balance(transactions).toStringAsFixed(2)}');
      buffer.writeln();
      buffer.writeln(
          '"${AppTranslations.of(context, 'date')}","${AppTranslations.of(context, 'category')}","${AppTranslations.of(context, 'description')}","${AppTranslations.of(context, 'type')}","${AppTranslations.of(context, 'amount')}"');

      for (var t in sortedTransactions) {
        final dateStr =
            DateFormat.yMMMd(locale).format(t.date);
        final cat = _csvEscape(t.category);
        final desc = _csvEscape(t.description ??
            AppTranslations.of(context, 'noDescription'));
        final typeStr = t.type == TransactionType.income
            ? AppTranslations.of(context, 'income')
            : AppTranslations.of(context, 'expense');
        final amt = t.amount.toStringAsFixed(2);
        buffer
            .writeln('"$dateStr","$cat","$desc","$typeStr",$amt');
      }

      final dir = await _getExportDirectory();
      final fileName =
          'Mino_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buffer.toString());

      if (mounted) {
        await Share.shareXFiles([XFile(file.path)],
            text: 'Pesa Tools Financial Report');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${AppTranslations.of(context, 'error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  List<Map<String, dynamic>> _monthlySummaryData(
      List<Transaction> transactions) {
    if (transactions.isEmpty) return [];
    final Map<DateTime, double> incomeMap = {};
    final Map<DateTime, double> expenseMap = {};

    for (var t in transactions) {
      final monthStart =
          DateTime(t.date.year, t.date.month, 1);
      if (t.type == TransactionType.income) {
        incomeMap.update(monthStart, (v) => v + t.amount,
            ifAbsent: () => t.amount);
      } else {
        expenseMap.update(monthStart, (v) => v + t.amount,
            ifAbsent: () => t.amount);
      }
    }

    final allMonths =
        {...incomeMap.keys, ...expenseMap.keys}.toList()
          ..sort((a, b) => a.compareTo(b));

    return allMonths.map((month) {
      final inc = incomeMap[month] ?? 0.0;
      final exp = expenseMap[month] ?? 0.0;
      return {
        'monthDate': month,
        'income': inc,
        'expense': exp,
        'total': inc + exp,
      };
    }).toList();
  }

  String _csvEscape(String field) =>
      field.replaceAll('"', '""');

  double _totalIncome(List<Transaction> tx) => tx
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);

  double _totalExpense(List<Transaction> tx) => tx
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double _balance(List<Transaction> tx) =>
      _totalIncome(tx) - _totalExpense(tx);

  Future<Directory> _getExportDirectory() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      try {
        return await getApplicationDocumentsDirectory();
      } catch (_) {
        final downloads =
            Directory('/storage/emulated/0/Download');
        if (await downloads.exists()) return downloads;
        return Directory.systemTemp;
      }
    }
  }
}