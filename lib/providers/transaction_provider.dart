import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'; // Keep if needed, otherwise can be removed
import '../models/transaction_model.dart';
import '../services/firestore_service.dart';
import 'auth_provider.dart';
import 'firestore_provider.dart';

/// Provides a stream of all transactions for the current user.
final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final firestore = ref.watch(firestoreServiceProvider);
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value([]);
  return firestore.getTransactionsForUser(user.uid);
});

/// Filter by transaction type (income/expense/all).
enum TransactionFilter { all, income, expense }

/// Selected transaction type filter.
final transactionFilterProvider = StateProvider<TransactionFilter>(
    (ref) => TransactionFilter.all);

/// Filtered transactions based on type only.
final filteredTransactionsProvider = Provider<List<Transaction>>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];
  final filter = ref.watch(transactionFilterProvider);
  switch (filter) {
    case TransactionFilter.income:
      return transactions.where((t) => t.type == TransactionType.income).toList();
    case TransactionFilter.expense:
      return transactions.where((t) => t.type == TransactionType.expense).toList();
    default:
      return transactions;
  }
});

/// Time period for filtering (week/month/quarter/year).
enum TimePeriod { week, month, quarter, year }

/// Selected time period.
final timePeriodProvider = StateProvider<TimePeriod>((ref) => TimePeriod.month);

/// Selected reference date for navigation.
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Helper to get start and end dates for a given period and reference date.
(DateTime start, DateTime end) _getDateRange(TimePeriod period, DateTime selectedDate) {
  switch (period) {
    case TimePeriod.week:
      // Week starts on Monday
      final start = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
      final startDate = DateTime(start.year, start.month, start.day);
      final endDate = startDate.add(const Duration(days: 7));
      return (startDate, endDate);
    case TimePeriod.month:
      final startDate = DateTime(selectedDate.year, selectedDate.month, 1);
      final endDate = DateTime(selectedDate.year, selectedDate.month + 1, 1);
      return (startDate, endDate);
    case TimePeriod.quarter:
      // Calculate which quarter the selected date falls in (1-4)
      int quarter = (selectedDate.month - 1) ~/ 3 + 1;
      final startDate = DateTime(selectedDate.year, (quarter - 1) * 3 + 1, 1);
      final endDate = DateTime(selectedDate.year, quarter * 3 + 1, 1);
      return (startDate, endDate);
    case TimePeriod.year:
      final startDate = DateTime(selectedDate.year, 1, 1);
      final endDate = DateTime(selectedDate.year + 1, 1, 1);
      return (startDate, endDate);
  }
}

/// Combined filter: applies both type and time period filters based on selected date.
final filteredTransactionsByPeriodProvider = Provider<List<Transaction>>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];
  final typeFilter = ref.watch(transactionFilterProvider);
  final period = ref.watch(timePeriodProvider);
  final selectedDate = ref.watch(selectedDateProvider);

  // Apply type filter first
  List<Transaction> typeFiltered;
  switch (typeFilter) {
    case TransactionFilter.income:
      typeFiltered = transactions.where((t) => t.type == TransactionType.income).toList();
      break;
    case TransactionFilter.expense:
      typeFiltered = transactions.where((t) => t.type == TransactionType.expense).toList();
      break;
    default:
      typeFiltered = transactions;
  }

  // Get date range based on period and selected date
  final (startDate, endDate) = _getDateRange(period, selectedDate);

  // Filter by date range (start inclusive, end exclusive)
  return typeFiltered.where((t) => 
    t.date.isAfter(startDate) && t.date.isBefore(endDate)
  ).toList();
});

/// Provider that returns the current date range label (e.g., "March 2025", "Week 10, 2025", "Q1 2025")
final dateRangeLabelProvider = Provider<String>((ref) {
  final period = ref.watch(timePeriodProvider);
  final selectedDate = ref.watch(selectedDateProvider);
  final (start, _) = _getDateRange(period, selectedDate);

  switch (period) {
    case TimePeriod.week:
      // Calculate week number (assuming week 1 starts on Jan 1)
      final weekNumber = ((start.difference(DateTime(start.year, 1, 1)).inDays / 7).ceil()).toString();
      return 'Week $weekNumber, ${start.year}';
    case TimePeriod.month:
      return '${_monthName(start.month)} ${start.year}';
    case TimePeriod.quarter:
      int quarter = (start.month - 1) ~/ 3 + 1;
      return 'Quarter$quarter ${start.year}';
    case TimePeriod.year:
      return start.year.toString();
  }
});

/// Helper to get month name from month number (1-12)
String _monthName(int month) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return months[month - 1];
}