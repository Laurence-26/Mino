import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/models/user_model.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/category_provider.dart';
import 'package:pesa_tools/providers/firestore_provider.dart';
import 'package:pesa_tools/screens/categories/category_management_screen.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionType? initialType;
  final String? groupId;

  const AddTransactionScreen({super.key, this.initialType, this.groupId});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  static const Color backgroundColor = Color(0xFF0E0B16);
  static const Color cardColor = Color(0xFF1A1625);
  static const Color accentColor = Color(0xFFC7B6FF);

  final _formKey = GlobalKey<FormState>();
  TransactionType _type = TransactionType.income;

  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) {
      _type = widget.initialType!;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          AppTranslations.of(context, 'addTransaction'),
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: backgroundColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null || user.uid.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return _buildForm(user);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (e, _) => Center(
          child: Text('${AppTranslations.of(context, 'error')}: $e',
              style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  Widget _buildForm(AppUser user) {
    final firestore = ref.watch(firestoreServiceProvider);
    final categoriesAsync = ref.watch(userCategoriesProvider(user.uid));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // ── TYPE SELECTOR ──────────────────────────────────────────────
            Card(
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTypeButton(
                        type: TransactionType.income,
                        icon: Icons.arrow_upward,
                        label: AppTranslations.of(context, 'income'),
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTypeButton(
                        type: TransactionType.expense,
                        icon: Icons.arrow_downward,
                        label: AppTranslations.of(context, 'expense'),
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── AMOUNT ─────────────────────────────────────────────────────
            _buildLabel(AppTranslations.of(context, 'amount')),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.attach_money, color: accentColor),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return AppTranslations.of(context, 'required');
                }
                final parsed = double.tryParse(value);
                if (parsed == null || parsed <= 0) {
                  return AppTranslations.of(context, 'invalidNumber');
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            // ── CATEGORY ───────────────────────────────────────────────────
            _buildLabel(AppTranslations.of(context, 'category')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: categoriesAsync.when(
                    data: (categoryMap) {
                      final categories = _type == TransactionType.income
                          ? (categoryMap['income'] ?? [])
                          : (categoryMap['expense'] ?? []);

                      // Reset selected category if it no longer exists in the list
                      if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _selectedCategory = null);
                        });
                      }

                      final List<DropdownMenuItem<String>> items = categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(_translateDefaultCategory(context, cat),
                              style: const TextStyle(color: Colors.white)),
                        );
                      }).toList()
                        ..add(DropdownMenuItem(
                          value: '__ADD_NEW__',
                          child: Row(
                            children: [
                              const Icon(Icons.add_circle_outline, size: 20, color: Colors.white70),
                              const SizedBox(width: 12),
                              Text(AppTranslations.of(context, 'addNewCategory'),
                                  style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ));

                      return DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        dropdownColor: cardColor,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: cardColor,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none),
                        ),
                        icon: const Icon(Icons.arrow_drop_down, color: accentColor),
                        items: items,
                        // BUG FIX: Added validator so the form cannot be submitted
                        // without a category, preventing the _selectedCategory! null crash.
                        validator: (value) {
                          if (value == null || value == '__ADD_NEW__') {
                            return AppTranslations.of(context, 'selectCategory');
                          }
                          return null;
                        },
                        onChanged: (value) async {
                          if (value == '__ADD_NEW__') {
                            final newCategory =
                            await _showAddCategoryDialog(context, user, _type);
                            if (newCategory != null) {
                              setState(() => _selectedCategory = newCategory);
                              ref.invalidate(userCategoriesProvider(user.uid));
                            }
                          } else {
                            setState(() => _selectedCategory = value);
                          }
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Text(AppTranslations.of(context, 'error'), style: const TextStyle(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14)),
                  child: IconButton(
                    icon: const Icon(Icons.tune, color: accentColor),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CategoryManagementScreen()),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── DESCRIPTION ────────────────────────────────────────────────
            _buildLabel(AppTranslations.of(context, 'description')),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: AppTranslations.of(context, 'descriptionHint'),
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 24),

            // ── DATE ───────────────────────────────────────────────────────
            _buildLabel(AppTranslations.of(context, 'date')),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 20, color: accentColor),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat.yMMMd().format(_selectedDate),
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── SAVE BUTTON ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : () => _save(firestore, user),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                  AppTranslations.of(context, 'saveTransaction'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// BUG FIX: Moved save logic into its own method with explicit null guard
  /// on _selectedCategory before using it (instead of the unsafe ! operator).
  Future<void> _save(dynamic firestore, AppUser user) async {
    if (!_formKey.currentState!.validate()) return;

    // Extra guard (validator already catches this, but belt-and-braces)
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTranslations.of(context, 'selectCategory'))),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final transaction = Transaction(
        id: const Uuid().v4(),
        userId: user.uid,
        amount: double.parse(_amountController.text.trim()),
        category: _selectedCategory!,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        date: _selectedDate,
        type: _type,
        addedBy: user.displayName ?? user.email,
      );

      if (widget.groupId != null) {
        await firestore.addGroupTransaction(widget.groupId!, transaction);
      } else {
        await firestore.addTransaction(transaction);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppTranslations.of(context, 'error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildTypeButton({
    required TransactionType type,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isSelected = _type == type;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: () => setState(() {
            _type = type;
            _selectedCategory = null;
          }),
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isSelected ? color : Colors.white54, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? color : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
    );
  }

  Future<String?> _showAddCategoryDialog(
      BuildContext context, AppUser user, TransactionType type) async {
    final controller = TextEditingController();
    final firestore = ref.read(firestoreServiceProvider);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(AppTranslations.of(context, 'addCategory'),
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: type == TransactionType.income
                ? AppTranslations.of(context, 'incomeCategoryHint')
                : AppTranslations.of(context, 'expenseCategoryHint'),
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: backgroundColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppTranslations.of(context, 'cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              await firestore.addCategory(user.uid, type, name);
              if (dialogContext.mounted) Navigator.pop(dialogContext, name);
            },
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            child: Text(AppTranslations.of(context, 'save')),
          ),
        ],
      ),
    );
  }

  String _translateDefaultCategory(BuildContext context, String category) {
    const Map<String, String> _keys = {
      'Salary': 'salary',
      'Freelance': 'freelance',
      'Business': 'business',
      'Investment': 'investment',
      'Gift': 'gift',
      'Rental': 'rental',
      'Dividend': 'dividend',
      'Bonus': 'bonus',
      'Other Income': 'otherIncome',
      'Groceries': 'groceries',
      'Transportation': 'transportation',
      'Utilities': 'utilities',
      'Rent': 'rent',
      'Other Expense': 'otherExpense',
    };
    final key = _keys[category];
    return key != null ? AppTranslations.of(context, key) : category;
  }
}
