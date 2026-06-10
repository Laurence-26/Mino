// providers/category_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/providers/firestore_provider.dart';
import 'package:pesa_tools/services/firestore_service.dart';
import 'auth_provider.dart';

final userCategoriesProvider = FutureProvider.family<Map<String, List<String>>, String?>((ref, userId) async {
  if (userId == null || userId.isEmpty) {
    return {
      'income': ['Salary', 'Freelance', 'Business', 'Investment', 'Gift', 'Rental', 'Dividend', 'Bonus', 'Other Income'],
      'expense': ['Groceries', 'Transportation', 'Utilities', 'Rent', 'Other Expense'],
    };
  }
  final firestore = ref.watch(firestoreServiceProvider);
  final categories = await firestore.getUserCategories(userId);
  if (categories != null) return categories;
  // Return default categories (keys will be translated via AppTranslations in the UI)
  return {
    'income': ['Salary', 'Freelance', 'Business', 'Investment', 'Gift', 'Rental', 'Dividend', 'Bonus', 'Other Income'],
    'expense': ['Groceries', 'Transportation', 'Utilities', 'Rent', 'Other Expense'],
  };
});