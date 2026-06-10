import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/firestore_provider.dart';

class EditTransactionScreen extends ConsumerStatefulWidget {
  final Transaction transaction;
  final String? groupId;

  const EditTransactionScreen({
    super.key,
    required this.transaction,
    this.groupId,
  });

  @override
  ConsumerState<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends ConsumerState<EditTransactionScreen> {
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;
  late String _selectedCategory;
  late TransactionType _type;
  late DateTime _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.transaction.amount.toString());
    _descriptionController = TextEditingController(text: widget.transaction.description ?? '');
    _selectedCategory = widget.transaction.category;
    _type = widget.transaction.type;
    _selectedDate = widget.transaction.date;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid amount')),
      );
      return;
    }
    if (_selectedCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final updatedTransaction = Transaction(
      id: widget.transaction.id,
      userId: widget.transaction.userId,
      amount: amount,
      category: _selectedCategory,
      description: _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
      date: _selectedDate,
      type: _type,
      addedBy: widget.transaction.addedBy,
    );

    try {
      final firestore = ref.read(firestoreServiceProvider);
      if (widget.groupId != null) {
        await firestore.updateGroupTransaction(widget.groupId!, updatedTransaction);
      } else {
        await firestore.updateTransaction(updatedTransaction);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Transaction')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    // Get categories (simplified – you can reuse the category provider)
    final categories = _type == TransactionType.income
        ? ['Salary', 'Freelance', 'Business', 'Investment', 'Gift', 'Rental', 'Dividend', 'Bonus', 'Other Income']
        : ['Groceries', 'Transportation', 'Utilities', 'Rent', 'Entertainment', 'Healthcare', 'Education', 'Other Expense'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Transaction'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _saveChanges,
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Type toggle
            Row(
              children: [
                Expanded(
                  child: _typeButton(TransactionType.income, Icons.arrow_upward, 'Income', Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _typeButton(TransactionType.expense, Icons.arrow_downward, 'Expense', Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Amount
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Category dropdown
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: categories.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat));
              }).toList(),
              onChanged: (value) => setState(() => _selectedCategory = value!),
            ),
            const SizedBox(height: 16),

            // Description
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Date picker
            ListTile(
              title: const Text('Date'),
              subtitle: Text(DateFormat.yMMMd().format(_selectedDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) setState(() => _selectedDate = date);
              },
            ),
          ],
        ),
      ),
      floatingActionButton: _isLoading
          ? const CircularProgressIndicator()
          : FloatingActionButton.extended(
              onPressed: _saveChanges,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
            ),
    );
  }

  Widget _typeButton(TransactionType type, IconData icon, String label, Color color) {
    final isSelected = _type == type;
    return OutlinedButton.icon(
      onPressed: () => setState(() => _type = type),
      icon: Icon(icon, color: isSelected ? color : null),
      label: Text(label, style: TextStyle(color: isSelected ? color : null)),
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? color.withOpacity(0.1) : null,
        side: BorderSide(color: isSelected ? color : Colors.grey),
      ),
    );
  }
}