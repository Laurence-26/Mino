enum TransactionType { income, expense }

class Transaction {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final String? description;
  final DateTime date;
  final TransactionType type;
  final String? addedBy;

  Transaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    this.description,
    required this.date,
    required this.type,
    this.addedBy,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'amount': amount,
        'category': category,
        'description': description,
        'date': date.toIso8601String(),
        'type': type.name,
        'addedBy': addedBy,
      };

  factory Transaction.fromMap(Map<String, dynamic> map) => Transaction(
        id: map['id'] ?? '',
        userId: map['userId'] ?? '',
        amount: (map['amount'] ?? 0.0).toDouble(),
        category: map['category'] ?? '',
        description: map['description'],
        date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
        type: map['type'] == 'income' ? TransactionType.income : TransactionType.expense,
        addedBy: map['addedBy'],
      );

  get currency => null;
}