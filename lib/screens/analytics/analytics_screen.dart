import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/providers/transaction_provider.dart';
import 'package:pesa_tools/providers/export_provider.dart';
import 'package:pesa_tools/providers/feature_flags_provider.dart';
import 'package:pesa_tools/providers/subscription_provider.dart';
import 'package:pesa_tools/services/revenue_cat_service.dart';
import 'package:pesa_tools/utils/currency_formatter.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../widgets/offline_banner.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

enum AnalysisPeriod { week, month, year, custom }

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  AnalysisPeriod _selectedPeriod = AnalysisPeriod.month;
  DateTimeRange? _customDateRange;
  bool _isExporting = false;

  late final Future<pw.Font> _baseFont = PdfGoogleFonts.openSansRegular();
  late final Future<pw.Font> _boldFont = PdfGoogleFonts.openSansBold();

  @override
  void initState() {
    super.initState();
  }

  DateTime _startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);
  DateTime _nextDay(DateTime date) => _startOfDay(date).add(const Duration(days: 1));

  DateTimeRange get _dateRange {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case AnalysisPeriod.week:
        final startOfWeek = _startOfDay(now.subtract(Duration(days: now.weekday - 1)));
        return DateTimeRange(start: startOfWeek, end: _nextDay(startOfWeek.add(const Duration(days: 6))));
      case AnalysisPeriod.month:
        final start = _startOfDay(DateTime(now.year, now.month, 1));
        final end = _nextDay(DateTime(now.year, now.month + 1, 1).subtract(const Duration(days: 1)));
        return DateTimeRange(start: start, end: end);
      case AnalysisPeriod.year:
        return DateTimeRange(
          start: _startOfDay(DateTime(now.year, 1, 1)),
          end: _nextDay(DateTime(now.year, 12, 31)),
        );
      case AnalysisPeriod.custom:
        if (_customDateRange == null) {
          final today = _startOfDay(now);
          return DateTimeRange(start: today, end: _nextDay(today));
        }
        return DateTimeRange(
          start: _startOfDay(_customDateRange!.start),
          end: _nextDay(_customDateRange!.end),
        );
    }
  }

  List<Transaction> _filterTransactions(List<Transaction> all) {
    final range = _dateRange;
    return all
        .where((t) =>
    t.date.isAfter(range.start.subtract(const Duration(days: 1))) &&
        t.date.isBefore(range.end))
        .toList();
  }

  Map<String, double> _categoryBreakdown(List<Transaction> transactions, TransactionType type) {
    final Map<String, double> breakdown = {};
    for (var t in transactions.where((t) => t.type == type)) {
      breakdown[t.category] = (breakdown[t.category] ?? 0) + t.amount;
    }
    return breakdown;
  }

  double _totalAmount(List<Transaction> transactions, TransactionType type) =>
      transactions.where((t) => t.type == type).fold(0.0, (sum, t) => sum + t.amount);

  // ── PDF EXPORT GATE ────────────────────────────────────────────
  Future<void> _handlePdfExport(List<Transaction> allTransactions) async {
    final paywallEnabled = await ref.read(paywallEnabledProvider.future);
    if (!paywallEnabled) {
      await _exportPdf(allTransactions);
      return;
    }

    final isPremium = await ref.read(isPremiumProvider.future);
    if (isPremium) {
      await _exportPdf(allTransactions);
      return;
    }

    final exportsRemaining = ref.read(exportProvider);
    if (exportsRemaining > 0) {
      final used = await ref.read(exportProvider.notifier).useExport();
      if (used) {
        await _exportPdf(allTransactions);
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
      await _exportPdf(allTransactions);
    }
  }

  // ── The actual PDF generation (unchanged from your original, but now called via gate) ──
  Future<void> _exportPdf(List<Transaction> allTransactions) async {
    final transactions = _filterTransactions(allTransactions);
    if (transactions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTranslations.of(context, 'noTransactionsToExport'))),
        );
      }
      return;
    }

    setState(() => _isExporting = true);
    try {
      final baseFont = await _baseFont;
      final boldFont = await _boldFont;

      final incomeTotal = _totalAmount(transactions, TransactionType.income);
      final expenseTotal = _totalAmount(transactions, TransactionType.expense);
      final net = incomeTotal - expenseTotal;
      final incomeBreakdown = _categoryBreakdown(transactions, TransactionType.income);
      final expenseBreakdown = _categoryBreakdown(transactions, TransactionType.expense);
      final periodLabel = _getPeriodLabel(context);

      final pdf = pw.Document(theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont));

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (_) => pw.Column(children: [
            pw.Text(AppTranslations.of(context, 'analysisReport'),
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('${AppTranslations.of(context, 'period')}: $periodLabel',
                style: pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 4),
            pw.Text(
                '${AppTranslations.of(context, 'generatedOn')}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 12),
          ]),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ),
          build: (_) => [
            pw.Text(AppTranslations.of(context, 'financialSummary'),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['', AppTranslations.of(context, 'amount')],
              data: [
                [AppTranslations.of(context, 'totalIncome'), formatCurrency(incomeTotal)],
                [AppTranslations.of(context, 'totalExpenses'), formatCurrency(expenseTotal)],
                [AppTranslations.of(context, 'netBalance'), formatCurrency(net)],
              ],
              border: null,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headerHeight: 30,
              cellHeight: 25,
              cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
            ),
            pw.SizedBox(height: 24),
            _pdfBreakdownTable(
                AppTranslations.of(context, 'incomeBreakdown'), incomeBreakdown, incomeTotal, context),
            pw.SizedBox(height: 24),
            _pdfBreakdownTable(
                AppTranslations.of(context, 'expenseBreakdown'), expenseBreakdown, expenseTotal, context),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final fileName = 'Mino_Analysis_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      if (mounted) {
        await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
            text: 'Pesa Tools Analysis Report');
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

  pw.Widget _pdfBreakdownTable(
      String title, Map<String, double> breakdown, double total, BuildContext context) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: [
          AppTranslations.of(context, 'category'),
          AppTranslations.of(context, 'amount'),
          AppTranslations.of(context, 'percentage'),
        ],
        data: breakdown.entries.map((entry) {
          final pct = total > 0 ? (entry.value / total) * 100 : 0;
          return [entry.key, formatCurrency(entry.value), '${pct.toStringAsFixed(1)}%'];
        }).toList(),
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
    ]);
  }

  String _getPeriodLabel(BuildContext context) {
    final range = _dateRange;
    final locale = Localizations.localeOf(context).toString();
    switch (_selectedPeriod) {
      case AnalysisPeriod.week:
        final start = DateFormat.yMMMd(locale).format(range.start);
        final end = DateFormat.yMMMd(locale).format(range.end.subtract(const Duration(days: 1)));
        return '$start – $end';
      case AnalysisPeriod.month:
        return DateFormat.yMMMM(locale).format(range.start);
      case AnalysisPeriod.year:
        return range.start.year.toString();
      case AnalysisPeriod.custom:
        final endDisplay = range.end.subtract(const Duration(days: 1));
        return '${DateFormat.yMMMd(locale).format(range.start)} – ${DateFormat.yMMMd(locale).format(endDisplay)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final exportsRemaining = ref.watch(exportProvider);
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final paywallEnabled = ref.watch(paywallEnabledProvider).value ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.of(context, 'analysis')),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: AppTranslations.of(context, 'exportPDF'),
              onPressed: () async {
                final all = transactionsAsync.value ?? [];
                await _handlePdfExport(all);   // gated export
              },
            ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // Export status banner — only when monetization is on.
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
                      Text('💎 Premium — Unlimited Exports',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    Text('$exportsRemaining free PDF exports remaining',
                        style: const TextStyle(color: Colors.blue)),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          Expanded(
            child: transactionsAsync.when(
              data: (allTransactions) {
                final filtered = _filterTransactions(allTransactions);
                final incomeTotal = _totalAmount(filtered, TransactionType.income);
                final expenseTotal = _totalAmount(filtered, TransactionType.expense);
                final net = incomeTotal - expenseTotal;
                final incomeBreakdown = _categoryBreakdown(filtered, TransactionType.income);
                final expenseBreakdown = _categoryBreakdown(filtered, TransactionType.expense);

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _periodChip(AnalysisPeriod.week, AppTranslations.of(context, 'week')),
                          _periodChip(AnalysisPeriod.month, AppTranslations.of(context, 'month')),
                          _periodChip(AnalysisPeriod.year, AppTranslations.of(context, 'year')),
                          _periodChip(AnalysisPeriod.custom, AppTranslations.of(context, 'custom')),
                        ],
                      ),
                    ),
                    if (_selectedPeriod == AnalysisPeriod.custom)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: InkWell(
                          onTap: _selectCustomDateRange,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.primaryColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_customDateRange == null
                                    ? AppTranslations.of(context, 'selectDateRange')
                                    : _getPeriodLabel(context)),
                                const Icon(Icons.calendar_today, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _summaryCard(context, AppTranslations.of(context, 'totalIncome'), incomeTotal, Colors.green),
                          const SizedBox(width: 12),
                          _summaryCard(context, AppTranslations.of(context, 'totalExpenses'), expenseTotal, Colors.red),
                          const SizedBox(width: 12),
                          _summaryCard(context, AppTranslations.of(context, 'netBalance'), net,
                              net >= 0 ? Colors.blue : Colors.orange),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          _buildCategoryBreakdownCard(
                              context,
                              AppTranslations.of(context, 'incomeBreakdown'),
                              incomeBreakdown,
                              incomeTotal,
                              Colors.green),
                          _buildCategoryBreakdownCard(
                              context,
                              AppTranslations.of(context, 'expenseBreakdown'),
                              expenseBreakdown,
                              expenseTotal,
                              Colors.red),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${AppTranslations.of(context, 'error')}: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdownCard(
      BuildContext context,
      String title,
      Map<String, double> breakdown,
      double total,
      Color primaryColor,
      ) {
    final entries = breakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: primaryColor, fontWeight: FontWeight.bold)),
            const Divider(),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text(AppTranslations.of(context, 'noDataForPeriod'))),
              )
            else
              ...entries.map((entry) {
                final percentage = total > 0 ? (entry.value / total) * 100 : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              flex: 3,
                              child: Text(entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.w500))),
                          Expanded(
                            flex: 2,
                            child: Text(formatCurrency(entry.value),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w500)),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text('(${percentage.toStringAsFixed(1)}%)',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? entry.value / total : 0,
                          backgroundColor: primaryColor.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _periodChip(AnalysisPeriod period, String label) {
    final isSelected = _selectedPeriod == period;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() {
        _selectedPeriod = period;
        if (period != AnalysisPeriod.custom) _customDateRange = null;
      }),
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
    );
  }

  Widget _summaryCard(BuildContext context, String title, double amount, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(formatCurrency(amount),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange,
    );
    if (picked != null) setState(() => _customDateRange = picked);
  }
}