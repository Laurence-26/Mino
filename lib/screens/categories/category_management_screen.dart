import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/category_provider.dart';
import 'package:pesa_tools/providers/firestore_provider.dart';
import 'package:pesa_tools/services/firestore_service.dart';

class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _categoryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppTranslations.of(context, 'manageCategories')),
        ),
        body: Center(
          child: Text(AppTranslations.of(context, 'loginRequired')),
        ),
      );
    }

    final categoriesAsync = ref.watch(userCategoriesProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.of(context, 'manageCategories')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: AppTranslations.of(context, 'incomeCategories')),
            Tab(text: AppTranslations.of(context, 'expenseCategories')),
          ],
        ),
      ),
      body: categoriesAsync.when(
        data: (categoryMap) {
          final incomeCategories = categoryMap['income'] ?? [];
          final expenseCategories = categoryMap['expense'] ?? [];
          return TabBarView(
            controller: _tabController,
            children: [
              _CategoryList(
                type: TransactionType.income,
                categories: incomeCategories,
                userId: user.uid,
                onCategoryAdded: _refreshCategories,
                onCategoryEdited: _refreshCategories,
                onCategoryDeleted: _refreshCategories,
              ),
              _CategoryList(
                type: TransactionType.expense,
                categories: expenseCategories,
                userId: user.uid,
                onCategoryAdded: _refreshCategories,
                onCategoryEdited: _refreshCategories,
                onCategoryDeleted: _refreshCategories,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Text('${AppTranslations.of(context, 'error')}: $e'),
        ),
      ),
    );
  }

  /// Refresh categories after any change by invalidating the provider.
  Future<void> _refreshCategories() async {
    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      ref.invalidate(userCategoriesProvider(user.uid));
    }
  }
}

/// Displays a list of categories for a specific type (income/expense)
/// with add, edit, delete functionality.
class _CategoryList extends ConsumerStatefulWidget {
  final TransactionType type;
  final List<String> categories;
  final String userId;
  final VoidCallback onCategoryAdded;
  final VoidCallback onCategoryEdited;
  final VoidCallback onCategoryDeleted;

  const _CategoryList({
    required this.type,
    required this.categories,
    required this.userId,
    required this.onCategoryAdded,
    required this.onCategoryEdited,
    required this.onCategoryDeleted,
  });

  @override
  ConsumerState<_CategoryList> createState() => __CategoryListState();
}

class __CategoryListState extends ConsumerState<_CategoryList> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Add button at the top
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _showAddCategoryDialog,
            icon: const Icon(Icons.add),
            label: Text(AppTranslations.of(context, 'addCategory')),
          ),
        ),
        // List of existing categories
        Expanded(
          child: widget.categories.isEmpty
              ? Center(
                  child: Text(
                    AppTranslations.of(context, 'noCategoriesYet'),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.categories.length,
                  itemBuilder: (context, index) {
                    final category = widget.categories[index];
                    return ListTile(
                      title: Text(category),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () =>
                                _showEditCategoryDialog(category, index),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () =>
                                _showDeleteConfirmation(category, index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Show dialog to add a new category.
  Future<void> _showAddCategoryDialog() async {
    _controller.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppTranslations.of(context, 'addCategory')),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppTranslations.of(context, 'categoryName'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppTranslations.of(context, 'cancel')),
          ),
          TextButton(
            onPressed: () {
              final name = _controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(dialogContext, name);
              }
            },
            child: Text(AppTranslations.of(context, 'save')),
          ),
        ],
      ),
    );

    if (result != null) {
      _addCategory(result);
    }
  }

  /// Add a new category to the list and save to Firestore.
  Future<void> _addCategory(String newCategory) async {
    final currentList = List<String>.from(widget.categories);
    if (currentList.contains(newCategory)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.of(context, 'categoryAlreadyExists')),
        ),
      );
      return;
    }

    currentList.add(newCategory);
    await _saveCategories(currentList);
    widget.onCategoryAdded();
  }

  /// Show dialog to edit an existing category.
  Future<void> _showEditCategoryDialog(String oldCategory, int index) async {
    _controller.text = oldCategory;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppTranslations.of(context, 'editCategory')),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppTranslations.of(context, 'categoryName'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppTranslations.of(context, 'cancel')),
          ),
          TextButton(
            onPressed: () {
              final name = _controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(dialogContext, name);
              }
            },
            child: Text(AppTranslations.of(context, 'save')),
          ),
        ],
      ),
    );

    if (result != null && result != oldCategory) {
      _editCategory(oldCategory, result, index);
    }
  }

  /// Replace an existing category with a new name.
  Future<void> _editCategory(
      String oldCategory, String newCategory, int index) async {
    final currentList = List<String>.from(widget.categories);
    if (oldCategory != newCategory && currentList.contains(newCategory)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.of(context, 'categoryAlreadyExists')),
        ),
      );
      return;
    }

    currentList[index] = newCategory;
    await _saveCategories(currentList);
    widget.onCategoryEdited();
  }

  /// Show confirmation dialog before deleting a category.
  Future<void> _showDeleteConfirmation(String category, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppTranslations.of(context, 'confirmDelete')),
        content: Text(
          AppTranslations.of(context, 'deleteCategoryConfirmation')
              .replaceFirst('{category}', category),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppTranslations.of(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppTranslations.of(context, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteCategory(index);
    }
  }

  /// Remove a category and save to Firestore.
  Future<void> _deleteCategory(int index) async {
    final currentList = List<String>.from(widget.categories);
    currentList.removeAt(index);
    await _saveCategories(currentList);
    widget.onCategoryDeleted();
  }

  /// Save the updated category list to Firestore.
  Future<void> _saveCategories(List<String> newList) async {
    final firestore = ref.read(firestoreServiceProvider);
    final currentMap = await firestore.getUserCategories(widget.userId) ??
        {
          'income': const [],
          'expense': const [],
        };

    final updatedMap = Map<String, List<String>>.from(currentMap);
    if (widget.type == TransactionType.income) {
      updatedMap['income'] = newList;
    } else {
      updatedMap['expense'] = newList;
    }

    await firestore.saveUserCategories(widget.userId, updatedMap);
  }
}